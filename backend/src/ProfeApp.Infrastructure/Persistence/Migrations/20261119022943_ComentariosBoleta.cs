using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class ComentariosBoleta : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "comentarios_boleta",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    seccion_id = table.Column<Guid>(type: "uuid", nullable: false),
                    alumno_id = table.Column<Guid>(type: "uuid", nullable: false),
                    parcial = table.Column<int>(type: "integer", nullable: false),
                    texto = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: false),
                    de_ia = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_comentarios_boleta", x => x.id);
                    table.ForeignKey(
                        name: "fk_comentarios_boleta_alumnos_alumno_id",
                        column: x => x.alumno_id,
                        principalTable: "alumnos",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_comentarios_boleta_secciones_seccion_id",
                        column: x => x.seccion_id,
                        principalTable: "secciones",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_comentarios_boleta_alumno_id",
                table: "comentarios_boleta",
                column: "alumno_id");

            migrationBuilder.CreateIndex(
                name: "ix_comentarios_boleta_seccion_id_alumno_id_parcial",
                table: "comentarios_boleta",
                columns: new[] { "seccion_id", "alumno_id", "parcial" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "comentarios_boleta");
        }
    }
}
