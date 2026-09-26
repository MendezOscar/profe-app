using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class Planes : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "registros",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    tipo = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    clase_clave = table.Column<string>(type: "character varying(600)", maxLength: 600, nullable: false),
                    clave = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    datos = table.Column<string>(type: "jsonb", nullable: true),
                    eliminado = table.Column<bool>(type: "boolean", nullable: false),
                    actualizado_en = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    modificado_en = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    tenant_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_registros", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "ix_registros_tenant_id_modificado_en",
                table: "registros",
                columns: new[] { "tenant_id", "modificado_en" });

            migrationBuilder.CreateIndex(
                name: "ix_registros_tenant_id_tipo_clase_clave_clave",
                table: "registros",
                columns: new[] { "tenant_id", "tipo", "clase_clave", "clave" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "registros");
        }
    }
}
