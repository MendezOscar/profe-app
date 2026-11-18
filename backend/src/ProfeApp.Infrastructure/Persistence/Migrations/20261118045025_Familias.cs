using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class Familias : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "codigos_familia",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    alumno_id = table.Column<Guid>(type: "uuid", nullable: false),
                    codigo = table.Column<string>(type: "character varying(12)", maxLength: 12, nullable: false),
                    expira_en = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_codigos_familia", x => x.id);
                    table.ForeignKey(
                        name: "fk_codigos_familia_alumnos_alumno_id",
                        column: x => x.alumno_id,
                        principalTable: "alumnos",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "comunicados",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    titulo = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    cuerpo = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: false),
                    seccion_ids = table.Column<List<Guid>>(type: "uuid[]", nullable: false),
                    autor_id = table.Column<Guid>(type: "uuid", nullable: true),
                    publicado_en = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_comunicados", x => x.id);
                    table.ForeignKey(
                        name: "fk_comunicados_instituciones_institucion_id",
                        column: x => x.institucion_id,
                        principalTable: "instituciones",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "vinculos_familiares",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    alumno_id = table.Column<Guid>(type: "uuid", nullable: false),
                    usuario_id = table.Column<Guid>(type: "uuid", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_vinculos_familiares", x => x.id);
                    table.ForeignKey(
                        name: "fk_vinculos_familiares_alumnos_alumno_id",
                        column: x => x.alumno_id,
                        principalTable: "alumnos",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_vinculos_familiares_asp_net_users_usuario_id",
                        column: x => x.usuario_id,
                        principalTable: "asp_net_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "lecturas_comunicados",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    comunicado_id = table.Column<Guid>(type: "uuid", nullable: false),
                    usuario_id = table.Column<Guid>(type: "uuid", nullable: false),
                    leido_en = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_lecturas_comunicados", x => x.id);
                    table.ForeignKey(
                        name: "fk_lecturas_comunicados_asp_net_users_usuario_id",
                        column: x => x.usuario_id,
                        principalTable: "asp_net_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_lecturas_comunicados_comunicados_comunicado_id",
                        column: x => x.comunicado_id,
                        principalTable: "comunicados",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_codigos_familia_alumno_id",
                table: "codigos_familia",
                column: "alumno_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_codigos_familia_codigo",
                table: "codigos_familia",
                column: "codigo",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_comunicados_institucion_id_publicado_en",
                table: "comunicados",
                columns: new[] { "institucion_id", "publicado_en" });

            migrationBuilder.CreateIndex(
                name: "ix_lecturas_comunicados_comunicado_id_usuario_id",
                table: "lecturas_comunicados",
                columns: new[] { "comunicado_id", "usuario_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_lecturas_comunicados_usuario_id",
                table: "lecturas_comunicados",
                column: "usuario_id");

            migrationBuilder.CreateIndex(
                name: "ix_vinculos_familiares_alumno_id_usuario_id",
                table: "vinculos_familiares",
                columns: new[] { "alumno_id", "usuario_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_vinculos_familiares_usuario_id",
                table: "vinculos_familiares",
                column: "usuario_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "codigos_familia");

            migrationBuilder.DropTable(
                name: "lecturas_comunicados");

            migrationBuilder.DropTable(
                name: "vinculos_familiares");

            migrationBuilder.DropTable(
                name: "comunicados");
        }
    }
}
