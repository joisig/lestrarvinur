# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BellaBooks (Bboo) is a Phoenix Framework 1.8 application with multi-tenant account management, authentication, and document digitization capabilities. The application uses Elixir, PostgreSQL, Tailwind CSS, and includes background job processing with Oban.

**Important:** See [ARCHITECTURE.md](./ARCHITECTURE.md) for key architectural decisions and their rationale, including currency handling, exchange rates, and multi-tenancy patterns.

## Development Commands

### Essential Commands
- `mix setup` - Install and setup dependencies (runs deps.get, ecto.setup, assets.setup, assets.build)
- `mix phx.server` - Start Phoenix server (visit localhost:4000)
- `iex -S mix phx.server` - Start Phoenix server with interactive shell
- `mix precommit` - Run all pre-commit checks (compile with warnings as errors, check unused deps, format, run tests)

### Database Commands
- `mix ecto.setup` - Create database, run migrations, and seed data
- `mix ecto.reset` - Drop and recreate database with seeds
- `mix ecto.migrate` - Run pending migrations
- `mix ecto.rollback` - Rollback last migration

### Testing & Quality
- `mix test` - Run all tests
- `mix test test/path/to/test.exs` - Run specific test file
- `mix test --failed` - Run previously failed tests
- `mix format` - Format code according to .formatter.exs
- `mix credo` - Run Credo linter for code quality checks
- `mix compile --warning-as-errors` - Compile with warnings treated as errors

### Asset Management
- `mix assets.setup` - Install Tailwind and ESBuild if missing
- `mix assets.build` - Build CSS and JavaScript assets
- `mix assets.deploy` - Build minified assets for production

## Architecture Overview

### Core Modules

#### Authentication & Accounts (`lib/bboo/accounts/`)
- Multi-tenant account system with invites
- User authentication via `phx.gen.auth` 
- Account-User relationship (many-to-many via UserAccount)
- Account invitations with expiry management
- User tokens for sessions and confirmations

#### Document Digitization (`lib/digz/`)
- `SupportingDocumentDigitizer` - Main orchestrator for document processing
- `RawDigitizer` - Handles raw digitization logic
- `VLM.OpenAI` - OpenAI Vision API integration for document analysis
- `Util.Image` - Image processing utilities using Tesseract OCR
- Supports PDFs, images, and scanned receipts

#### Background Jobs (`lib/bboo/workers/`)
- `DeleteExpiredInvites` - Cleans up expired account invitations
- `DigitizeEmailDemoWorker` - Processes inbound emails with attachments
- Uses Oban for reliable job processing

#### Web Layer (`lib/bboo_web/`)
- Phoenix LiveView 1.1.0 for interactive UI
- Authentication plugs: `:fetch_current_user`, `:require_authenticated_user`
- Live sessions: `:current_user` (optional auth), `:require_authenticated_user` (required auth)
- Email handling with inbound controller and demo interfaces

### Key Design Patterns

1. **Authentication Flow**: Router-level authentication with proper redirects and live_session scopes. Always use `@current_scope.user` in templates, never `@current_user`.

2. **LiveView Conventions**: 
   - LiveViews named with `Live` suffix (e.g., `HomeLive`)
   - Use streams for collections to avoid memory issues
   - Forms use `to_form/2` with changesets

3. **Multi-tenancy**: Users belong to multiple accounts via `UserAccount` join table. Account selection handled via `AccountSelectionController`.

4. **Email Processing**: Inbound emails received at `/inbound-email` endpoint, attachments digitized via background jobs.

## Important Guidelines from AGENTS.md

- Use `mix precommit` before finalizing changes
- Use `:req` library for HTTP requests (already included)
- Phoenix 1.8 specific:
  - Always begin LiveView templates with `<Layouts.app flash={@flash} ...>`
  - Use `<.icon name="hero-x-mark">` for icons, not Heroicons modules
  - Use imported `<.input>` component from core_components.ex
- Never use `@current_user` - always use `@current_scope.user`
- LiveView routes must be in correct `live_session` blocks
- Use LiveView streams for collections, not regular lists
- Forms must use `to_form/2` pattern with `@form[:field]` access

## Coding Standards

- For functions that are part of a module's public interface, use a @doc docstring.
- For functions that you might think to use defp for, still use def so they can be tested more easily. No docstring needed, just put a comment: # Not part of public API (and include any other usage instructions
  as normal comment lines below that).

## Internationalization / localization (i18n / l10n)

- Use gettext to retrieve any message that will be shown to users.

## DK+ Data Migration Guidelines

### Important: When modifying dkplus_general_ledger_transactions or dkplus_vendor_transactions tables

These tables store `raw_data` JSONB from the DK+ API. When adding or modifying columns:

1. **Always create a data migration** to populate existing rows from raw_data
2. **Check the raw_data structure** to understand available fields
3. **Common fields in raw_data**:
   - `JournalDate` - The transaction date
   - `Text` - Description
   - `Reference` - Reference number
   - `Amount` - Transaction amount
   - `LedgerAccount` - GL account number
   - `Vendor` - Vendor ID
   - `DueDate` - Due date for vendor transactions
   - `IsCredit` - Boolean indicating credit/debit

Example migration pattern:
```elixir
# Update existing rows from raw_data when adding/fixing a field
execute """
  UPDATE dkplus_vendor_transactions
  SET date = (raw_data->>'JournalDate')::date
  WHERE date IS NULL AND raw_data->>'JournalDate' IS NOT NULL
"""
```

This ensures data consistency when we discover new field mappings or fix parsing issues.

## Dependencies & External Services

- **Database**: PostgreSQL via Ecto
- **Background Jobs**: Oban for reliable job processing
- **HTTP Client**: Req library (preferred over HTTPoison/Tesla)
- **Email**: Swoosh for email delivery, Mail for parsing
- **OCR**: Tesseract OCR for text extraction from images
- **Vision API**: OpenAI API for document understanding (requires API key)
- **Frontend**: Tailwind CSS, ESBuild, Phoenix LiveView

An important part of our coding standard: WE DO NOT USE defp functions in Elixir, we only use def. Reason is testability and accessibility from the REPL. Instead you may add a comment (not a docstring) before the function header that's like `# Not intended for use outside this module`