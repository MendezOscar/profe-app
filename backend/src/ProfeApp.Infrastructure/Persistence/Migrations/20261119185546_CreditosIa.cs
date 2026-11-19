using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class CreditosIa : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "medios",
                table: "usos_ia",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "medios",
                table: "tandas_ia",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "paginas",
                table: "tandas_ia",
                type: "jsonb",
                nullable: false,
                defaultValue: "{}");

            // Lo ya usado pasa a créditos (en medios) con la misma tabla de CreditosIa.
            migrationBuilder.Sql("""
                UPDATE usos_ia SET medios = CASE funcion
                  WHEN 'examen' THEN 8 WHEN 'plan' THEN 6 WHEN 'calificar' THEN 4 WHEN 'calificar_tanda' THEN 2
                  WHEN 'informe' THEN 6 WHEN 'pregunta' THEN 3 ELSE 1 END;
                UPDATE tandas_ia SET medios = trabajos * 2 WHERE estado = 'procesando';
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "medios",
                table: "usos_ia");

            migrationBuilder.DropColumn(
                name: "medios",
                table: "tandas_ia");

            migrationBuilder.DropColumn(
                name: "paginas",
                table: "tandas_ia");
        }
    }
}
