using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class Escala : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "modificado_en",
                table: "clase_valores",
                type: "timestamp with time zone",
                nullable: false,
                defaultValue: new DateTimeOffset(new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified), new TimeSpan(0, 0, 0, 0, 0)));

            // Las celdas que ya existían: su última hora conocida es la de captura.
            migrationBuilder.Sql("UPDATE clase_valores SET modificado_en = actualizado_en;");

            migrationBuilder.CreateIndex(
                name: "ix_clase_valores_clase_id_modificado_en",
                table: "clase_valores",
                columns: new[] { "clase_id", "modificado_en" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ix_clase_valores_clase_id_modificado_en",
                table: "clase_valores");

            migrationBuilder.DropColumn(
                name: "modificado_en",
                table: "clase_valores");
        }
    }
}
