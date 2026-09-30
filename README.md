# MCP Desktop Automation

A Model Context Protocol server and toolkit for desktop automation. It provides two main layers of functionality:
1. **Node.js MCP Server**: General purpose tools for screen capture, mouse/keyboard control.
2. **PowerShell Scripts**: specialized, robust automation for Telegram Desktop (handling encoding, window focus, etc.).

## Configuration

Here's how to configure Claude Desktop to use this MCP server.

### Local Development (Recommended)

Since you are running this from source:

```json
{
  "mcpServers": {
    "desktop-automation": {
      "command": "bun",
      "args": ["D:\\Data\\Documents\\Programming\\Projects\\MCP\\mcp-desktop-automation\\server.js"]
    }
  }
}
```

### NPX (If published)

```json
{
  "mcpServers": {
    "desktop-automation": {
      "command": "npx",
      "args": ["-y", "mcp-desktop-automation"]
    }
  }
}
```

### Permissions

This server requires system-level permissions to:
* Capture screenshots of your screen
* Control mouse movement and clicks
* Simulate keyboard input

## Telegram Automation (PowerShell)

The core automation logic for Telegram resides in the `scripts/` directory. These are optimized for Windows/PowerShell execution.

### 1. Send Message to Current Chat (`send_telegram_v7.ps1`)

Sends a text message to the currently open chat in Telegram.

**Usage:**

```powershell
.\scripts\send_telegram_v7.ps1 -Message "Your Message Here"
```

**For Non-ASCII Characters (Cyrillic, Emojis):**
**CRITICAL**: To avoid encoding issues in the shell, encode your message in Base64 (UTF-8) and use the `-Base64` switch.

```powershell
# Example: Sending "Привет 🌍"
# Base64 for "Привет 🌍" is "0J/RgNC40LLQtdGCIPCfjI0="
.\scripts\send_telegram_v7.ps1 -Message "0J/RgNC40LLQtdGCIPCfjI0=" -Base64
```

### 2. Search Contact and Send Message (`send_telegram_search_send.ps1`)

Searches for a user/chat, opens it, and sends a message.

**Usage:**

```powershell
.\scripts\send_telegram_search_send.ps1 -SearchTerm "John Doe" -Message "Hello"
```

**With Base64 (Recommended for complexity):**

```powershell
.\scripts\send_telegram_search_send.ps1 -SearchTerm "Vladimir" -Message "Base64EncodedString..." -Base64
```

**Process Flow:**
1. Focuses Telegram.
2. Clicks the "Search" bar (top left).
3. Types the `-SearchTerm`.
4. Clicks the first result.
5. Clicks the message input field.
6. Pastes and sends the `-Message`.
7. Saves a screenshot to `.tmp/` for verification.

## Node.js Server Components

The `server.js` provides the following tools for general automation:

- **screen_capture**: Captures the current screen content.
- **keyboard_press**: Presses a keyboard key (e.g., 'enter', 'a', 'control').
- **keyboard_type**: Types text at the current cursor position.
- **mouse_click**: Performs a mouse click (left/right/middle, double).
- **mouse_move**: Moves the mouse to specified coordinates.
- **get_screen_size**: Gets the screen dimensions.

## Prerequisites

- **OS**: Windows (PowerShell 7+ recommended, but 5.1 works)
- **Application**: Telegram Desktop installed and logged in.
- **Node.js**: (>=14.x)

## Project Structure

- `scripts/`: Contains the PowerShell automation scripts.
- `.tmp/`: Stores temporary files, primarily verification screenshots. Set `MCP_SCREENSHOT_DIR` to save screenshots taken without an explicit path somewhere else; the directory is created if missing.
- `server.js`: Main MCP server implementation.

## MCP Agent Instructions

1. **Always use Base64** for message content if it contains anything other than simple English ASCII. This guarantees that emojis and Russian text are transmitted correctly.
2. **Check the Exit Code**: If the script returns `0`, it ran successfully.
3. **Verify via Screenshot**: The scripts output the path to a screenshot (e.g., `.tmp/2025...capture.png`). Read this file or listing the directory to confirm the visual state if needed.

## License

MIT
