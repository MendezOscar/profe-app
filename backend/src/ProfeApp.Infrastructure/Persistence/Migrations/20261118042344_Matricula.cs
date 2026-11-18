using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class Matricula : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "alumnos",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    identidad = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    nombre = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    fecha_nacimiento = table.Column<DateOnly>(type: "date", nullable: true),
                    sexo = table.Column<string>(type: "character varying(1)", maxLength: 1, nullable: true),
                    direccion = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: true),
                    salud = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    notas = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_alumnos", x => x.id);
                    table.ForeignKey(
                        name: "fk_alumnos_instituciones_institucion_id",
                        column: x => x.institucion_id,
                        principalTable: "instituciones",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "encargados",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    alumno_id = table.Column<Guid>(type: "uuid", nullable: false),
                    nombre = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    parentesco = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    telefono = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: true),
                    correo = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: true),
                    principal = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_encargados", x => x.id);
                    table.ForeignKey(
                        name: "fk_encargados_alumnos_alumno_id",
                        column: x => x.alumno_id,
                        principalTable: "alumnos",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "matriculas",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    alumno_id = table.Column<Guid>(type: "uuid", nullable: false),
                    anio_lectivo_id = table.Column<Guid>(type: "uuid", nullable: false),
                    seccion_id = table.Column<Guid>(type: "uuid", nullable: false),
                    tipo = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    estado = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    fecha_ingreso = table.Column<DateOnly>(type: "date", nullable: false),
                    fecha_baja = table.Column<DateOnly>(type: "date", nullable: true),
                    motivo_baja = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_matriculas", x => x.id);
                    table.ForeignKey(
                        name: "fk_matriculas_alumnos_alumno_id",
                        column: x => x.alumno_id,
                        principalTable: "alumnos",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_matriculas_anios_lectivos_anio_lectivo_id",
                        column: x => x.anio_lectivo_id,
                        principalTable: "anios_lectivos",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_matriculas_secciones_seccion_id",
                        column: x => x.seccion_id,
                        principalTable: "secciones",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_alumnos_institucion_id_identidad",
                table: "alumnos",
                columns: new[] { "institucion_id", "identidad" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_encargados_alumno_id",
                table: "encargados",
                column: "alumno_id");

            migrationBuilder.CreateIndex(
                name: "ix_matriculas_alumno_id_anio_lectivo_id",
                table: "matriculas",
                columns: new[] { "alumno_id", "anio_lectivo_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_matriculas_anio_lectivo_id",
                table: "matriculas",
                column: "anio_lectivo_id");

            migrationBuilder.CreateIndex(
                name: "ix_matriculas_seccion_id_estado",
                table: "matriculas",
                columns: new[] { "seccion_id", "estado" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "encargados");

            migrationBuilder.DropTable(
                name: "matriculas");

            migrationBuilder.DropTable(
                name: "alumnos");
        }
    }
}
