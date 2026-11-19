using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class TandasIa : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "tandas_ia",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    usuario_id = table.Column<Guid>(type: "uuid", nullable: false),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: true),
                    actividad = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    lote = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    trabajos = table.Column<int>(type: "integer", nullable: false),
                    puntos = table.Column<decimal>(type: "numeric(6,2)", precision: 6, scale: 2, nullable: false),
                    estado = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    resultados = table.Column<string>(type: "jsonb", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_tandas_ia", x => x.id);
                    table.ForeignKey(
                        name: "fk_tandas_ia_asp_net_users_usuario_id",
                        column: x => x.usuario_id,
                        principalTable: "asp_net_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_tandas_ia_estado",
                table: "tandas_ia",
                column: "estado");

            migrationBuilder.CreateIndex(
                name: "ix_tandas_ia_usuario_id_actividad",
                table: "tandas_ia",
                columns: new[] { "usuario_id", "actividad" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "tandas_ia");
        }
    }
}
