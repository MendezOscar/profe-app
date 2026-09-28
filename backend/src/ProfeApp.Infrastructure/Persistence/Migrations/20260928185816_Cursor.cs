using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class Cursor : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ix_registros_tenant_id_modificado_en",
                table: "registros");

            migrationBuilder.CreateIndex(
                name: "ix_registros_tenant_id_modificado_en_id",
                table: "registros",
                columns: new[] { "tenant_id", "modificado_en", "id" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ix_registros_tenant_id_modificado_en_id",
                table: "registros");

            migrationBuilder.CreateIndex(
                name: "ix_registros_tenant_id_modificado_en",
                table: "registros",
                columns: new[] { "tenant_id", "modificado_en" });
        }
    }
}
