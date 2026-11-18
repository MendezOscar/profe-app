using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class Conducta : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "conductas",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    seccion_id = table.Column<Guid>(type: "uuid", nullable: false),
                    alumno_id = table.Column<Guid>(type: "uuid", nullable: false),
                    parcial = table.Column<int>(type: "integer", nullable: false),
                    nota = table.Column<string>(type: "character varying(1)", maxLength: 1, nullable: false),
                    puesta_por = table.Column<Guid>(type: "uuid", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_conductas", x => x.id);
                    table.ForeignKey(
                        name: "fk_conductas_alumnos_alumno_id",
                        column: x => x.alumno_id,
                        principalTable: "alumnos",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_conductas_secciones_seccion_id",
                        column: x => x.seccion_id,
                        principalTable: "secciones",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_conductas_alumno_id",
                table: "conductas",
                column: "alumno_id");

            migrationBuilder.CreateIndex(
                name: "ix_conductas_seccion_id_alumno_id_parcial",
                table: "conductas",
                columns: new[] { "seccion_id", "alumno_id", "parcial" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "conductas");
        }
    }
}
