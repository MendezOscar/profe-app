# syntax=docker/dockerfile:1

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Primero solo los csproj: asi el restore queda en cache mientras no cambien las dependencias.
COPY Directory.Build.props ./
COPY src/ProfeApp.Domain/ProfeApp.Domain.csproj src/ProfeApp.Domain/
COPY src/ProfeApp.Application/ProfeApp.Application.csproj src/ProfeApp.Application/
COPY src/ProfeApp.Infrastructure/ProfeApp.Infrastructure.csproj src/ProfeApp.Infrastructure/
COPY src/ProfeApp.Api/ProfeApp.Api.csproj src/ProfeApp.Api/
RUN dotnet restore src/ProfeApp.Api/ProfeApp.Api.csproj

COPY src/ src/
RUN dotnet publish src/ProfeApp.Api/ProfeApp.Api.csproj -c Release -o /app --no-restore


FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime

# tzdata: el reloj resuelve America/Tegucigalpa por nombre y falla sin la base de zonas.
# curl: lo usa el healthcheck de Docker.
RUN apt-get update \
    && apt-get install -y --no-install-recommends tzdata curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app ./
USER $APP_UID

# El plan gratuito tiene poca memoria: el recolector de escritorio ocupa mucho menos.
ENV DOTNET_gcServer=0 \
    DOTNET_GCConserveMemory=5 \
    ASPNETCORE_ENVIRONMENT=Production \
    ASPNETCORE_HTTP_PORTS=8080

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD curl -fsS http://localhost:8080/health/live || exit 1

ENTRYPOINT ["dotnet", "ProfeApp.Api.dll"]
