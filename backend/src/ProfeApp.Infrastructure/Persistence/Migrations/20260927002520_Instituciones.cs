using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class Instituciones : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "institucion_id",
                table: "asp_net_users",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "instituciones",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    nombre = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    plan = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    max_docentes = table.Column<int>(type: "integer", nullable: false),
                    vence_en = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    activa = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_instituciones", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "ix_asp_net_users_institucion_id",
                table: "asp_net_users",
                column: "institucion_id");

            migrationBuilder.AddForeignKey(
                name: "fk_asp_net_users_instituciones_institucion_id",
                table: "asp_net_users",
                column: "institucion_id",
                principalTable: "instituciones",
                principalColumn: "id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "fk_asp_net_users_instituciones_institucion_id",
                table: "asp_net_users");

            migrationBuilder.DropTable(
                name: "instituciones");

            migrationBuilder.DropIndex(
                name: "ix_asp_net_users_institucion_id",
                table: "asp_net_users");

            migrationBuilder.DropColumn(
                name: "institucion_id",
                table: "asp_net_users");
        }
    }
}
