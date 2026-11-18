using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class EstructuraCentro : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "cargo",
                table: "asp_net_users",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "anios_lectivos",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    anio = table.Column<int>(type: "integer", nullable: false),
                    inicio = table.Column<DateOnly>(type: "date", nullable: false),
                    fin = table.Column<DateOnly>(type: "date", nullable: false),
                    cierre_parcial1 = table.Column<DateOnly>(type: "date", nullable: true),
                    cierre_parcial2 = table.Column<DateOnly>(type: "date", nullable: true),
                    cierre_parcial3 = table.Column<DateOnly>(type: "date", nullable: true),
                    cierre_parcial4 = table.Column<DateOnly>(type: "date", nullable: true),
                    actual = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_anios_lectivos", x => x.id);
                    table.ForeignKey(
                        name: "fk_anios_lectivos_instituciones_institucion_id",
                        column: x => x.institucion_id,
                        principalTable: "instituciones",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "aulas",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    nombre = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    capacidad = table.Column<int>(type: "integer", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_aulas", x => x.id);
                    table.ForeignKey(
                        name: "fk_aulas_instituciones_institucion_id",
                        column: x => x.institucion_id,
                        principalTable: "instituciones",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "grados",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    nivel = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    nombre = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    orden = table.Column<int>(type: "integer", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_grados", x => x.id);
                    table.ForeignKey(
                        name: "fk_grados_instituciones_institucion_id",
                        column: x => x.institucion_id,
                        principalTable: "instituciones",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "asignaturas_grado",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    grado_id = table.Column<Guid>(type: "uuid", nullable: false),
                    nombre = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    orden = table.Column<int>(type: "integer", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_asignaturas_grado", x => x.id);
                    table.ForeignKey(
                        name: "fk_asignaturas_grado_grados_grado_id",
                        column: x => x.grado_id,
                        principalTable: "grados",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "secciones",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    anio_lectivo_id = table.Column<Guid>(type: "uuid", nullable: false),
                    grado_id = table.Column<Guid>(type: "uuid", nullable: false),
                    nombre = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    jornada = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    cupo = table.Column<int>(type: "integer", nullable: true),
                    aula_id = table.Column<Guid>(type: "uuid", nullable: true),
                    maestro_guia_id = table.Column<Guid>(type: "uuid", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_secciones", x => x.id);
                    table.ForeignKey(
                        name: "fk_secciones_anios_lectivos_anio_lectivo_id",
                        column: x => x.anio_lectivo_id,
                        principalTable: "anios_lectivos",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_secciones_asp_net_users_maestro_guia_id",
                        column: x => x.maestro_guia_id,
                        principalTable: "asp_net_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "fk_secciones_aulas_aula_id",
                        column: x => x.aula_id,
                        principalTable: "aulas",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "fk_secciones_grados_grado_id",
                        column: x => x.grado_id,
                        principalTable: "grados",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "cargas_docentes",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    seccion_id = table.Column<Guid>(type: "uuid", nullable: false),
                    asignatura_grado_id = table.Column<Guid>(type: "uuid", nullable: false),
                    docente_id = table.Column<Guid>(type: "uuid", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_cargas_docentes", x => x.id);
                    table.ForeignKey(
                        name: "fk_cargas_docentes_asignaturas_grado_asignatura_grado_id",
                        column: x => x.asignatura_grado_id,
                        principalTable: "asignaturas_grado",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_cargas_docentes_asp_net_users_docente_id",
                        column: x => x.docente_id,
                        principalTable: "asp_net_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_cargas_docentes_secciones_seccion_id",
                        column: x => x.seccion_id,
                        principalTable: "secciones",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_anios_lectivos_actual",
                table: "anios_lectivos",
                column: "institucion_id",
                unique: true,
                filter: "actual");

            migrationBuilder.CreateIndex(
                name: "ix_anios_lectivos_institucion_id_anio",
                table: "anios_lectivos",
                columns: new[] { "institucion_id", "anio" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_asignaturas_grado_grado_id_nombre",
                table: "asignaturas_grado",
                columns: new[] { "grado_id", "nombre" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_asignaturas_grado_institucion_id",
                table: "asignaturas_grado",
                column: "institucion_id");

            migrationBuilder.CreateIndex(
                name: "ix_aulas_institucion_id_nombre",
                table: "aulas",
                columns: new[] { "institucion_id", "nombre" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_cargas_docentes_asignatura_grado_id",
                table: "cargas_docentes",
                column: "asignatura_grado_id");

            migrationBuilder.CreateIndex(
                name: "ix_cargas_docentes_docente_id",
                table: "cargas_docentes",
                column: "docente_id");

            migrationBuilder.CreateIndex(
                name: "ix_cargas_docentes_seccion_id_asignatura_grado_id",
                table: "cargas_docentes",
                columns: new[] { "seccion_id", "asignatura_grado_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_grados_institucion_id_nombre",
                table: "grados",
                columns: new[] { "institucion_id", "nombre" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_secciones_anio_lectivo_id_grado_id_jornada_nombre",
                table: "secciones",
                columns: new[] { "anio_lectivo_id", "grado_id", "jornada", "nombre" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_secciones_aula_id",
                table: "secciones",
                column: "aula_id");

            migrationBuilder.CreateIndex(
                name: "ix_secciones_grado_id",
                table: "secciones",
                column: "grado_id");

            migrationBuilder.CreateIndex(
                name: "ix_secciones_institucion_id",
                table: "secciones",
                column: "institucion_id");

            migrationBuilder.CreateIndex(
                name: "ix_secciones_maestro_guia_id",
                table: "secciones",
                column: "maestro_guia_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "cargas_docentes");

            migrationBuilder.DropTable(
                name: "asignaturas_grado");

            migrationBuilder.DropTable(
                name: "secciones");

            migrationBuilder.DropTable(
                name: "anios_lectivos");

            migrationBuilder.DropTable(
                name: "aulas");

            migrationBuilder.DropTable(
                name: "grados");

            migrationBuilder.DropColumn(
                name: "cargo",
                table: "asp_net_users");
        }
    }
}
