#!/bin/zsh
# Base local en blanco: docente demo sin clases y sin vencimiento. BORRA la base local de desarrollo.
S=${0:a:h}
LOG=${TMPDIR:-/tmp}/profeapp-api.log
pkill -f "ProfeApp.Api"; sleep 2
docker exec profeapp-db psql -q -U profeapp -d postgres -c "drop database if exists profeapp with (force);" -c "create database profeapp owner profeapp;"
cd $S/../../backend
ASPNETCORE_ENVIRONMENT=Development App__CorsOrigins__0=http://localhost:8099 nohup dotnet run --project src/ProfeApp.Api --urls http://localhost:5081 > $LOG 2>&1 &
for i in {1..60}; do curl -s -o /dev/null localhost:5081/health/live && break; sleep 2; done
sleep 3
docker exec profeapp-db psql -q -U profeapp -d profeapp -c "update tenants set pagado_hasta = null where id = (select tenant_id from asp_net_users where email='docente@demo.hn');"
echo listo
