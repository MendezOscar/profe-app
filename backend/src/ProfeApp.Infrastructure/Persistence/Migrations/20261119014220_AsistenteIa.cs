using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AsistenteIa : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "con_ia",
                table: "tenants",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "con_ia",
                table: "instituciones",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.CreateTable(
                name: "usos_ia",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    usuario_id = table.Column<Guid>(type: "uuid", nullable: false),
                    institucion_id = table.Column<Guid>(type: "uuid", nullable: true),
                    funcion = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    modelo = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    tokens_entrada = table.Column<int>(type: "integer", nullable: false),
                    tokens_salida = table.Column<int>(type: "integer", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_usos_ia", x => x.id);
                    table.ForeignKey(
                        name: "fk_usos_ia_asp_net_users_usuario_id",
                        column: x => x.usuario_id,
                        principalTable: "asp_net_users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_usos_ia_institucion_id_created_at",
                table: "usos_ia",
                columns: new[] { "institucion_id", "created_at" });

            migrationBuilder.CreateIndex(
                name: "ix_usos_ia_usuario_id_created_at",
                table: "usos_ia",
                columns: new[] { "usuario_id", "created_at" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "usos_ia");

            migrationBuilder.DropColumn(
                name: "con_ia",
                table: "tenants");

            migrationBuilder.DropColumn(
                name: "con_ia",
                table: "instituciones");
        }
    }
}
