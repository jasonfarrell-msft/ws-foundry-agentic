# Build the MCP server
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS builder

WORKDIR /src
COPY MCP.Server.csproj .
RUN dotnet restore

COPY Program.cs .
RUN dotnet publish -c Release -o /app/publish

# Runtime image
FROM mcr.microsoft.com/dotnet/aspnet:8.0

WORKDIR /app
COPY --from=builder /app/publish .

ENV PORT=8001
ENV AUDIT_API_URL=http://localhost:8000

EXPOSE 8001

ENTRYPOINT ["dotnet", "MCP.Server.dll"]
