using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class Horario : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "bloques_horario",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    jornada = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    orden = table.Column<int>(type: "integer", nullable: false),
                    inicio = table.Column<TimeOnly>(type: "time without time zone", nullable: false),
                    fin = table.Column<TimeOnly>(type: "time without time zone", nullable: false),
                    es_receso = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_bloques_horario", x => x.id);
                    table.ForeignKey(
                        name: "fk_bloques_horario_instituciones_institucion_id",
                        column: x => x.institucion_id,
                        principalTable: "instituciones",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "tomas_asistencia_diaria",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    seccion_id = table.Column<Guid>(type: "uuid", nullable: false),
                    fecha = table.Column<DateOnly>(type: "date", nullable: false),
                    tomada_por = table.Column<Guid>(type: "uuid", nullable: false),
                    tomada_en = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_tomas_asistencia_diaria", x => x.id);
                    table.ForeignKey(
                        name: "fk_tomas_asistencia_diaria_secciones_seccion_id",
                        column: x => x.seccion_id,
                        principalTable: "secciones",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "horarios_clase",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    seccion_id = table.Column<Guid>(type: "uuid", nullable: false),
                    dia = table.Column<int>(type: "integer", nullable: false),
                    bloque_id = table.Column<Guid>(type: "uuid", nullable: false),
                    asignatura_grado_id = table.Column<Guid>(type: "uuid", nullable: false),
                    aula_id = table.Column<Guid>(type: "uuid", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_horarios_clase", x => x.id);
                    table.ForeignKey(
                        name: "fk_horarios_clase_asignaturas_grado_asignatura_grado_id",
                        column: x => x.asignatura_grado_id,
                        principalTable: "asignaturas_grado",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_horarios_clase_aulas_aula_id",
                        column: x => x.aula_id,
                        principalTable: "aulas",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "fk_horarios_clase_bloques_horario_bloque_id",
                        column: x => x.bloque_id,
                        principalTable: "bloques_horario",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_horarios_clase_secciones_seccion_id",
                        column: x => x.seccion_id,
                        principalTable: "secciones",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "marcas_asistencia_diaria",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    toma_id = table.Column<Guid>(type: "uuid", nullable: false),
                    alumno_id = table.Column<Guid>(type: "uuid", nullable: false),
                    estado = table.Column<string>(type: "character varying(1)", maxLength: 1, nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_marcas_asistencia_diaria", x => x.id);
                    table.ForeignKey(
                        name: "fk_marcas_asistencia_diaria_alumnos_alumno_id",
                        column: x => x.alumno_id,
                        principalTable: "alumnos",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_marcas_asistencia_diaria_tomas_asistencia_diaria_toma_id",
                        column: x => x.toma_id,
                        principalTable: "tomas_asistencia_diaria",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_bloques_horario_institucion_id_jornada_orden",
                table: "bloques_horario",
                columns: new[] { "institucion_id", "jornada", "orden" });

            migrationBuilder.CreateIndex(
                name: "ix_horarios_clase_asignatura_grado_id",
                table: "horarios_clase",
                column: "asignatura_grado_id");

            migrationBuilder.CreateIndex(
                name: "ix_horarios_clase_aula_id",
                table: "horarios_clase",
                column: "aula_id");

            migrationBuilder.CreateIndex(
                name: "ix_horarios_clase_bloque_id",
                table: "horarios_clase",
                column: "bloque_id");

            migrationBuilder.CreateIndex(
                name: "ix_horarios_clase_institucion_id_dia",
                table: "horarios_clase",
                columns: new[] { "institucion_id", "dia" });

            migrationBuilder.CreateIndex(
                name: "ix_horarios_clase_seccion_id_dia_bloque_id",
                table: "horarios_clase",
                columns: new[] { "seccion_id", "dia", "bloque_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_marcas_asistencia_diaria_alumno_id",
                table: "marcas_asistencia_diaria",
                column: "alumno_id");

            migrationBuilder.CreateIndex(
                name: "ix_marcas_asistencia_diaria_toma_id_alumno_id",
                table: "marcas_asistencia_diaria",
                columns: new[] { "toma_id", "alumno_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_tomas_asistencia_diaria_seccion_id_fecha",
                table: "tomas_asistencia_diaria",
                columns: new[] { "seccion_id", "fecha" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "horarios_clase");

            migrationBuilder.DropTable(
                name: "marcas_asistencia_diaria");

            migrationBuilder.DropTable(
                name: "bloques_horario");

            migrationBuilder.DropTable(
                name: "tomas_asistencia_diaria");
        }
    }
}
