using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class IaMultiplicador : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "ia_multiplicador",
                table: "tenants",
                type: "integer",
                nullable: false,
                defaultValue: 1);

            migrationBuilder.AddColumn<int>(
                name: "ia_multiplicador",
                table: "instituciones",
                type: "integer",
                nullable: false,
                defaultValue: 1);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ia_multiplicador",
                table: "tenants");

            migrationBuilder.DropColumn(
                name: "ia_multiplicador",
                table: "instituciones");
        }
    }
}
