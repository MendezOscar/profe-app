using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class Sync : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "clases",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    clave = table.Column<string>(type: "character varying(600)", maxLength: 600, nullable: false),
                    codigo_centro = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    centro = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    modalidad = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    grado_seccion = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: true),
                    jornada = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: true),
                    asignatura = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: true),
                    hoja = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    archivo_nombre = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                    archivo = table.Column<byte[]>(type: "bytea", nullable: false),
                    plantilla_actualizada_en = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    plantilla_modificada_en = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    modificado_en = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    eliminada_en = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    tenant_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_clases", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "clase_alumnos",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    clase_id = table.Column<Guid>(type: "uuid", nullable: false),
                    clave = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    identidad = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    documento = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    nombre = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    fila = table.Column<int>(type: "integer", nullable: false),
                    orden = table.Column<int>(type: "integer", nullable: false),
                    activo = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    tenant_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_clase_alumnos", x => x.id);
                    table.ForeignKey(
                        name: "fk_clase_alumnos_clases_clase_id",
                        column: x => x.clase_id,
                        principalTable: "clases",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "clase_columnas",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    clase_id = table.Column<Guid>(type: "uuid", nullable: false),
                    clave = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    grupo = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    nombre = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    tipo = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    col = table.Column<int>(type: "integer", nullable: false),
                    orden = table.Column<int>(type: "integer", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    tenant_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_clase_columnas", x => x.id);
                    table.ForeignKey(
                        name: "fk_clase_columnas_clases_clase_id",
                        column: x => x.clase_id,
                        principalTable: "clases",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "clase_valores",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    clase_id = table.Column<Guid>(type: "uuid", nullable: false),
                    alumno_clave = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    columna_clave = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    valor = table.Column<int>(type: "integer", nullable: true),
                    actualizado_en = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    tenant_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_clase_valores", x => x.id);
                    table.ForeignKey(
                        name: "fk_clase_valores_clases_clase_id",
                        column: x => x.clase_id,
                        principalTable: "clases",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_clase_alumnos_clase_id_clave",
                table: "clase_alumnos",
                columns: new[] { "clase_id", "clave" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_clase_columnas_clase_id_clave",
                table: "clase_columnas",
                columns: new[] { "clase_id", "clave" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_clase_valores_clase_id_alumno_clave_columna_clave",
                table: "clase_valores",
                columns: new[] { "clase_id", "alumno_clave", "columna_clave" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_clases_tenant_id_clave",
                table: "clases",
                columns: new[] { "tenant_id", "clave" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_clases_tenant_id_modificado_en",
                table: "clases",
                columns: new[] { "tenant_id", "modificado_en" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "clase_alumnos");

            migrationBuilder.DropTable(
                name: "clase_columnas");

            migrationBuilder.DropTable(
                name: "clase_valores");

            migrationBuilder.DropTable(
                name: "clases");
        }
    }
}
