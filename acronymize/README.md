# Acronymize
![Bash](https://img.shields.io/badge/language-bash-green) ![License: MIT](https://img.shields.io/badge/license-MIT-yellow)

Generate a playful "acronym expansion" from input text by mapping each letter (in order) to a randomly selected dictionary word that starts with that letter.

## Features

- Readable output for multi-word input: prints one output line per input word
- Per-occurrence randomization: repeated letters can produce different words within the same run
- Input sanitization: splits input on whitespace to preserve word boundaries and removes non-alphabetic characters from each word before processing
- Title Case output: each generated word is capitalized (first letter uppercased)
- Efficient implementation: scans the wordlist once and performs all selection in `awk` (no per-letter external pipelines)
- Custom wordlists via `-w /path/to/wordlist` or the `WORDLIST` environment variable

## Requirements

- Bash
- `awk`
- A wordlist file (default: `/usr/share/dict/words`)

On many Linux systems, `/usr/share/dict/words` is provided by a package commonly named `words` (or similar). If your system does not have a default wordlist, provide one using `-w` or `WORDLIST`.

## Installation

Clone the repository and make the script executable:

```bash
chmod +x acronymize.sh
```

## Usage

```bash
./acronymize.sh [-w WORDLIST] [text...]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-w PATH` | Use a custom wordlist | `/usr/share/dict/words` |

The `WORDLIST` environment variable can also be used to set the wordlist path. The `-w` flag overrides the environment variable.

### Examples

Single word:

```bash
./acronymize.sh test
```

Multiple words (quotes optional):

```bash
./acronymize.sh Make Acronyms Great Again
```

Custom wordlist using `-w`:

```bash
./acronymize.sh -w ./words.txt "hello world"
```

Custom wordlist using `WORDLIST`:

```bash
WORDLIST=./words.txt ./acronymize.sh hello world
```

Input with non-alphabetic characters (they are stripped before processing):

```bash
./acronymize.sh "Hello, world!"
```

Possible output:

```
Horizon Ember Lantern Lichen Orbit
Warden Orbit Rivulet Lantern Druid
```

## Configuration

### Output format

- Each input word becomes one output line.
- Each letter in the input word becomes one output word.
- Non-alphabetic characters are removed from each input word before processing.

### Word selection behavior

For each letter occurrence:

1. The script selects a random dictionary word that begins with that letter.
2. Repeated letters are randomized independently.

To reduce short-run repetition for the same starting letter, candidate words for a given letter are shuffled and consumed sequentially, then reshuffled when exhausted.

### Handling missing matches

If no dictionary entry matches a given letter, the script emits a placeholder token: `(no-match:x)`.

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Wordlist not readable |
| `2` | Invalid usage (missing input or no alphabetic characters) |

## Credits

**Author:** Leon "Avic" Simmons -- [GitHub](https://github.com/Avicennasis)
