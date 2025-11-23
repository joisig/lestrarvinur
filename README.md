# Lestrarvinur (Reading Buddy) - Phoenix LiveView Version

A flashcard reading app to help children learn Icelandic words, reimplemented from the TypeScript/React version as an Elixir Phoenix LiveView application with SQLite backend.

## Features

- **Username-based Authentication**: Simple login/register system using usernames (no passwords, no email)
- **Four Word Lists**: Yellow, Blue, Red, and Green lists with Icelandic sight words
- **Progress Tracking**: Tracks total words read with database persistence
- **Trophy System**: 8 unlockable trophies at various word thresholds
- **Prestige Mode**: Reset and replay after reaching 10,000 words
- **Encouragement Messages**: 30 pre-defined Icelandic encouragement phrases (shown every 10 words)
- **Audio Support**:
  - Upload custom human-recorded audio for any word
  - Upload audio for encouragement messages
  - Supports multiple audio formats (MP3, WebM, WAV, M4A, OGG)
- **Admin Dashboard**: Accessible only to `joi@joisig.com` for recording/uploading audio files

## Architecture

### Technology Stack

- **Backend**: Elixir + Phoenix Framework 1.8
- **Frontend**: Phoenix LiveView 1.1 (no separate frontend framework)
- **Database**: SQLite via Ecto
- **Styling**: TailwindCSS with custom animations
- **Audio**: HTML5 Audio API for playback

### Directory Structure

```
lib/
├── lestrarvinur_phoenix/
│   ├── accounts/          # User authentication and management
│   │   └── user.ex        # User schema
│   ├── accounts.ex        # Accounts context
│   ├── constants.ex       # Word lists, trophies, encouragement messages
│   ├── media.ex           # Audio file storage/retrieval
│   └── repo.ex           # Ecto repository
├── lestrarvinur_phoenix_web/
│   ├── live/             # LiveView modules
│   │   ├── auth_live.ex         # Login/Register
│   │   ├── dashboard_live.ex    # User dashboard with trophies
│   │   ├── game_live.ex         # Flashcard game
│   │   └── admin_live.ex        # Admin audio upload interface
│   ├── router.ex         # Route definitions
│   └── ...
priv/
├── repo/
│   └── migrations/       # Database migrations
└── static/
    └── media/            # Audio file storage
        ├── words/        # Word pronunciations
        └── encouragements/  # Encouragement message audio
```

## Setup

### Prerequisites

- Elixir 1.18+ and Erlang 28+
- SQLite3

### Installation

1. Install dependencies:
   ```bash
   cd lestrarvinur_phoenix
   mix deps.get
   ```

2. Create and migrate the database:
   ```bash
   mix ecto.create
   mix ecto.migrate
   ```

3. Install and build assets:
   ```bash
   mix assets.setup
   mix assets.build
   ```

4. Start the Phoenix server:
   ```bash
   mix phx.server
   ```

   Or with IEx for interactive development:
   ```bash
   iex -S mix phx.server
   ```

5. Visit [`localhost:4000`](http://localhost:4000) in your browser.

## Usage

### For Students

1. **Register**: Enter any username (can include spaces, is case-sensitive)
2. **Dashboard**: View your total words read and unlocked trophies
3. **Play**: Click "SPILA" to start the flashcard game
4. **Read Words**:
   - Tap the speaker icon to hear the word (if audio is available)
   - Tap anywhere else on the screen to advance to the next word
5. **Earn Trophies**: Unlock trophies at various milestones (100, 200, 400, 600, 800, 1000, 1500, 2000 words)
6. **Encouragements**: Receive encouraging messages every 10 words

### For Admins (joi@joisig.com only)

1. **Login** with username `joi@joisig.com`
2. **Click "Stjórnborð"** (Admin Dashboard) button
3. **Upload Audio Files**:
   - For words: Click the upload icon next to any word, select an audio file
   - For encouragements: Click the upload icon next to any encouragement message
4. **Play/Delete**: Use the play button to preview, trash button to delete

## Game Logic

### Word Progression

1. Words are presented in shuffled groups by color category (Yellow → Blue → Red → Green)
2. Each color group is shuffled internally
3. After completing all 4 groups, they reshuffle and repeat

### Progress Tracking

- Each word read increments the total count
- Progress persists across sessions in SQLite database
- Session streak resets when user logs out

### Trophy Unlocking

Trophies unlock automatically at these thresholds:
- **Byrjandi** (Beginner): 100 words
- **Lestrarhestur** (Reading Horse): 200 words
- **Snillingur** (Genius): 400 words
- **Meistari** (Master): 600 words
- **Stjarna** (Star): 800 words
- **Ofurhetja** (Superhero): 1000 words
- **Galdramaður** (Wizard): 1500 words
- **Goðsögn** (Legend): 2000 words

### Prestige Mode

At 10,000 words:
- Counter resets to 0
- Trophies reset (can be earned again)
- Special "x2" badge appears on trophies
- Prestige status persists

## Differences from TypeScript Version

### Changes

1. **No AI at Runtime**:
   - TypeScript version used Gemini AI for text-to-speech and encouragement generation
   - Phoenix version uses pre-recorded audio files and static encouragement messages

2. **Username Instead of Email**:
   - Authentication uses arbitrary usernames (case-sensitive, can include spaces)
   - No email validation required

3. **Reduced Encouragements**:
   - 30 static messages instead of AI-generated ones

4. **File Upload Instead of Recording**:
   - Admin uploads audio files instead of recording directly in browser
   - More flexible - supports multiple audio formats

5. **Server-Side State**:
   - Progress stored in SQLite database instead of localStorage
   - More reliable and accessible across devices

### Similarities

- Same word lists (89 words total across 4 categories)
- Same trophy system and thresholds
- Same game progression logic
- Same visual design and styling
- Same encouragement frequency (every 10 words)

## Development

### Running Tests

```bash
mix test
```

### Code Formatting

```bash
mix format
```

### Database Operations

```bash
# Reset database
mix ecto.reset

# Create migration
mix ecto.gen.migration migration_name

# Run migrations
mix ecto.migrate

# Rollback migration
mix ecto.rollback
```

### Asset Compilation

```bash
# Development (watch mode)
mix phx.server  # Assets auto-compile on change

# Production build
mix assets.deploy
```

## File Structure for Audio

Audio files are stored in `priv/static/media/` with predetermined filenames:

### Words
```
priv/static/media/words/word_<word>.<ext>
```
Example: `word_hún.webm`, `word_það.mp3`

### Encouragements
```
priv/static/media/encouragements/encouragement_<index>.<ext>
```
Example: `encouragement_0.webm` (for "Vel gert!")

Supported formats: `.webm`, `.mp3`, `.wav`, `.m4a`, `.ogg`

## Configuration

The following constants can be modified in `lib/lestrarvinur_phoenix/constants.ex`:

- **Word Lists**: Add/remove/modify Icelandic words by category
- **Trophies**: Change trophy names, thresholds, or colors
- **Encouragements**: Modify the 30 encouragement messages
- **Prestige Threshold**: Default is 10,000 words
- **Admin Username**: Default is "joi@joisig.com"

## License

This is an educational application for learning Icelandic reading.

## Credits

- Original TypeScript/React version created with AI Studio
- Phoenix LiveView reimplementation by Claude Code
