using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class Incidencias : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "incidencias",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    alumno_id = table.Column<Guid>(type: "uuid", nullable: false),
                    seccion_id = table.Column<Guid>(type: "uuid", nullable: true),
                    fecha = table.Column<DateOnly>(type: "date", nullable: false),
                    gravedad = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    descripcion = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: false),
                    medida = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    seguimiento = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    cerrada = table.Column<bool>(type: "boolean", nullable: false),
                    registrada_por = table.Column<Guid>(type: "uuid", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_incidencias", x => x.id);
                    table.ForeignKey(
                        name: "fk_incidencias_alumnos_alumno_id",
                        column: x => x.alumno_id,
                        principalTable: "alumnos",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_incidencias_secciones_seccion_id",
                        column: x => x.seccion_id,
                        principalTable: "secciones",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateIndex(
                name: "ix_incidencias_alumno_id_fecha",
                table: "incidencias",
                columns: new[] { "alumno_id", "fecha" });

            migrationBuilder.CreateIndex(
                name: "ix_incidencias_institucion_id_fecha",
                table: "incidencias",
                columns: new[] { "institucion_id", "fecha" });

            migrationBuilder.CreateIndex(
                name: "ix_incidencias_registrada_por",
                table: "incidencias",
                column: "registrada_por");

            migrationBuilder.CreateIndex(
                name: "ix_incidencias_seccion_id",
                table: "incidencias",
                column: "seccion_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "incidencias");
        }
    }
}
