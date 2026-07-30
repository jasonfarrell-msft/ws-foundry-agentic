from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import sqlite3
import json
import os
from pathlib import Path
import logging

# Logging setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Audit API", version="1.0.0")

# Database configuration
DB_PATH = "/tmp/audit.db"
CONFIG_PATH = "/app/audit_config.json"

# Data models
class ViolationCause(BaseModel):
    description: str

class AuditArea(BaseModel):
    id: str
    name: str
    rating: str  # "Compliant", "At Risk", "Non-compliant"
    violation_causes: List[str]

class AuditScorecard(BaseModel):
    areas: List[AuditArea]

class AuditUpdate(BaseModel):
    rating: str
    violation_causes: List[str]

# Database initialization
def init_db():
    """Initialize SQLite database and load config data."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Create table if not exists
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS audit_areas (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            rating TEXT NOT NULL,
            violation_causes TEXT NOT NULL
        )
    ''')
    
    # Load config and seed data
    try:
        with open(CONFIG_PATH, 'r') as f:
            config = json.load(f)
        
        # Clear existing data
        cursor.execute('DELETE FROM audit_areas')
        
        # Insert config data
        for area in config['audit_areas']:
            causes_json = json.dumps(area.get('violation_causes', []))
            cursor.execute('''
                INSERT INTO audit_areas (id, name, rating, violation_causes)
                VALUES (?, ?, ?, ?)
            ''', (area['id'], area['name'], area['rating'], causes_json))
        
        conn.commit()
        logger.info(f"Database initialized with {len(config['audit_areas'])} audit areas")
    except FileNotFoundError:
        logger.warning(f"Config file not found at {CONFIG_PATH}. Using empty database.")
    except json.JSONDecodeError:
        logger.error(f"Invalid JSON in config file.")
    finally:
        conn.close()

def get_audit_area(area_id: str) -> Optional[AuditArea]:
    """Retrieve a single audit area by ID."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('SELECT id, name, rating, violation_causes FROM audit_areas WHERE id = ?', (area_id,))
    row = cursor.fetchone()
    conn.close()
    
    if row:
        return AuditArea(
            id=row[0],
            name=row[1],
            rating=row[2],
            violation_causes=json.loads(row[3])
        )
    return None

def get_all_audit_areas() -> List[AuditArea]:
    """Retrieve all audit areas."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('SELECT id, name, rating, violation_causes FROM audit_areas')
    rows = cursor.fetchall()
    conn.close()
    
    areas = []
    for row in rows:
        areas.append(AuditArea(
            id=row[0],
            name=row[1],
            rating=row[2],
            violation_causes=json.loads(row[3])
        ))
    return areas

def update_audit_area(area_id: str, rating: str, violation_causes: List[str]) -> bool:
    """Update an audit area's rating and violation causes."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    causes_json = json.dumps(violation_causes)
    cursor.execute('''
        UPDATE audit_areas SET rating = ?, violation_causes = ?
        WHERE id = ?
    ''', (rating, causes_json, area_id))
    conn.commit()
    conn.close()
    return cursor.rowcount > 0

# Endpoints
@app.on_event("startup")
async def startup_event():
    """Initialize database on startup."""
    init_db()
    logger.info("Audit API started")

@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "healthy"}

@app.get("/scorecard", response_model=AuditScorecard)
async def get_scorecard():
    """Get the complete audit scorecard."""
    areas = get_all_audit_areas()
    return AuditScorecard(areas=areas)

@app.get("/audit/{area_id}", response_model=AuditArea)
async def get_audit_area_detail(area_id: str):
    """Get details for a specific audit area."""
    area = get_audit_area(area_id)
    if not area:
        raise HTTPException(status_code=404, detail=f"Audit area '{area_id}' not found")
    return area

@app.put("/audit/{area_id}", response_model=AuditArea)
async def update_audit_area_detail(area_id: str, update: AuditUpdate):
    """Update a specific audit area."""
    # Verify area exists
    existing = get_audit_area(area_id)
    if not existing:
        raise HTTPException(status_code=404, detail=f"Audit area '{area_id}' not found")
    
    # Update the area
    success = update_audit_area(area_id, update.rating, update.violation_causes)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to update audit area")
    
    # Return updated area
    return get_audit_area(area_id)

@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "service": "Audit API",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "scorecard": "/scorecard",
            "audit_area": "/audit/{area_id}",
            "update_area": "PUT /audit/{area_id}"
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
