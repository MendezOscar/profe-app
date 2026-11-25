using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ProfeApp.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class ElDocumentoDeLaMensualidad : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "rtn",
                table: "tenants",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "cai_documento",
                table: "pagos",
                type: "character varying(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "documento_id",
                table: "pagos",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "documento_intentado_el",
                table: "pagos",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "error_documento",
                table: "pagos",
                type: "character varying(300)",
                maxLength: 300,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "numero_documento",
                table: "pagos",
                type: "character varying(40)",
                maxLength: 40,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "rtn",
                table: "instituciones",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "ix_pagos_numero_documento",
                table: "pagos",
                column: "numero_documento");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ix_pagos_numero_documento",
                table: "pagos");

            migrationBuilder.DropColumn(
                name: "rtn",
                table: "tenants");

            migrationBuilder.DropColumn(
                name: "cai_documento",
                table: "pagos");

            migrationBuilder.DropColumn(
                name: "documento_id",
                table: "pagos");

            migrationBuilder.DropColumn(
                name: "documento_intentado_el",
                table: "pagos");

            migrationBuilder.DropColumn(
                name: "error_documento",
                table: "pagos");

            migrationBuilder.DropColumn(
                name: "numero_documento",
                table: "pagos");

            migrationBuilder.DropColumn(
                name: "rtn",
                table: "instituciones");
        }
    }
}
