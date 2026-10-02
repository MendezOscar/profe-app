using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class Cobros : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "como_pagar",
                table: "tenants",
                type: "character varying(500)",
                maxLength: 500,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "dias_gracia",
                table: "tenants",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<decimal>(
                name: "monto",
                table: "tenants",
                type: "numeric(12,2)",
                precision: 12,
                scale: 2,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<string>(
                name: "nivel",
                table: "tenants",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<DateOnly>(
                name: "pagado_hasta",
                table: "tenants",
                type: "date",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "plan_nombre",
                table: "tenants",
                type: "character varying(80)",
                maxLength: 80,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "como_pagar",
                table: "instituciones",
                type: "character varying(500)",
                maxLength: 500,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "dias_gracia",
                table: "instituciones",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<decimal>(
                name: "monto",
                table: "instituciones",
                type: "numeric(12,2)",
                precision: 12,
                scale: 2,
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<DateOnly>(
                name: "pagado_hasta",
                table: "instituciones",
                type: "date",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "plan_nombre",
                table: "instituciones",
                type: "character varying(80)",
                maxLength: 80,
                nullable: true);

            // La fecha de vencimiento de la licencia pasa a ser el último día pagado, en hora de Honduras.
            migrationBuilder.Sql(
                "UPDATE instituciones SET pagado_hasta = (vence_en AT TIME ZONE 'America/Tegucigalpa')::date WHERE vence_en IS NOT NULL;");

            migrationBuilder.DropColumn(
                name: "vence_en",
                table: "instituciones");

            migrationBuilder.CreateTable(
                name: "pagos",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    cuenta_id = table.Column<Guid>(type: "uuid", nullable: false),
                    pagado_el = table.Column<DateOnly>(type: "date", nullable: false),
                    monto = table.Column<decimal>(type: "numeric(12,2)", precision: 12, scale: 2, nullable: false),
                    periodos = table.Column<int>(type: "integer", nullable: false),
                    cubre_hasta = table.Column<DateOnly>(type: "date", nullable: false),
                    referencia = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    created_by = table.Column<Guid>(type: "uuid", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    updated_by = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_pagos", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "ix_pagos_cuenta_id_pagado_el",
                table: "pagos",
                columns: new[] { "cuenta_id", "pagado_el" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "pagos");

            migrationBuilder.DropColumn(
                name: "como_pagar",
                table: "tenants");

            migrationBuilder.DropColumn(
                name: "dias_gracia",
                table: "tenants");

            migrationBuilder.DropColumn(
                name: "monto",
                table: "tenants");

            migrationBuilder.DropColumn(
                name: "nivel",
                table: "tenants");

            migrationBuilder.DropColumn(
                name: "pagado_hasta",
                table: "tenants");

            migrationBuilder.DropColumn(
                name: "plan_nombre",
                table: "tenants");

            migrationBuilder.DropColumn(
                name: "como_pagar",
                table: "instituciones");

            migrationBuilder.DropColumn(
                name: "dias_gracia",
                table: "instituciones");

            migrationBuilder.DropColumn(
                name: "monto",
                table: "instituciones");

            migrationBuilder.DropColumn(
                name: "pagado_hasta",
                table: "instituciones");

            migrationBuilder.DropColumn(
                name: "plan_nombre",
                table: "instituciones");

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "vence_en",
                table: "instituciones",
                type: "timestamp with time zone",
                nullable: true);
        }
    }
}
