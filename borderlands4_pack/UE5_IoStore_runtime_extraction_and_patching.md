# UE5 IoStore Offline Asset Analysis and Runtime Extraction

This document describes a general workflow for locating assets in Unreal
Engine 5 IoStore containers, invoking the game's own decompression wrapper when
a standalone Oodle decoder is unavailable, comparing original and override
assets, and modifying fixed-length values without changing the container
layout.

## 1. Roles of the three file types

UE5 games and mods commonly use three files with the same base name:

- `.pak`: A traditional Pak container or container-discovery entry point. In
  IoStore projects, it may be very small and contain only mount information,
  indexes, or a small amount of non-IoStore data. Some games discover the
  `.pak` first and then load the matching IoStore sidecar files.
- `.utoc`: The IoStore directory. It records chunk IDs, logical offsets and
  lengths, physical offsets of compression blocks, compressed and
  uncompressed sizes, compression methods, the directory index, and container
  flags.
- `.ucas`: The IoStore data area. Asset contents and container-header chunks
  are generally stored here.

The `.utoc` and `.ucas` files are an inseparable pair. Even if a modification
changes only a few bytes in the `.ucas`, the original `.pak` and `.utoc`
usually still need to be installed because the game relies on them to discover
the container and locate its data. The `.utoc` only needs to be rebuilt when
repacking or changing chunk lengths, offsets, compression methods, or the
directory structure. A fixed-length in-place modification can usually reuse
it.

## 2. Confirm the container properties first

Read the `.utoc` header and confirm:

1. The IoStore version and header length.
2. The number of chunks and compression blocks.
3. The compression-block size, commonly `0x10000`.
4. The compression method name, such as `Oodle`.
5. Whether the container has the Indexed, Compressed, Encrypted, or Signed
   flags set.
6. The size and location of the Directory Index.

Encrypted containers require an AES key, while signed containers are not
suitable for direct modification. Unsigned, unencrypted override containers
are the best candidates for fixed-length patches.

## 3. Parse the directory index

The Directory Index generally contains:

1. A Mount Point string.
2. A Directory Entry array.
3. A File Entry array.
4. A String Table.

Find the target filename in the String Table, then obtain the TOC Entry index
from the corresponding File Entry's `UserData`. Read the following values from
that TOC Entry:

- Chunk ID;
- logical offset;
- chunk length.

Be aware that different fields may use different byte orders or compact
encodings. Cross-check the interpretation against a known small container
instead of inferring it from a single value.

## 4. Locate compression blocks

After determining the chunk's logical offset:

```text
FirstBlock = floor(LogicalOffset / CompressionBlockSize)
LastBlock  = floor((LogicalOffset + Length - 1) / CompressionBlockSize)
```

A compression-block entry generally provides:

- the physical offset in the `.ucas`;
- the compressed size;
- the uncompressed size;
- the compression-method index.

After reading the physical location, check that the stream header is stable
and confirm that the compressed data does not extend beyond the end of the
`.ucas` file.

## 5. Oodle limitations

Oodle is a proprietary compression library with no official, fully compatible
open-source implementation. Some reverse-engineered implementations support
only certain encoders and versions. If a game does not ship with a standalone
`oo2core` dynamic library, the decoder may be statically linked into the main
executable.

There are three possible approaches in that situation:

1. Use an existing asset tool that supports the game's version.
2. Use a compatible standalone Oodle dynamic library.
3. Invoke the game's own Oodle wrapper function.

The third approach carries the most risk. Its entry point and parameters must
be verified; do not simply assume one of the common Oodle function signatures
found online.

## 6. Recover the game's decompression wrapper

Start by looking for game-code call sites that invoke the underlying decoder.
The ideal wrapper has only four parameters:

```text
Decode(compressedPointer, compressedSize, outputPointer, outputSize)
```

The wrapper supplies the optional parameters required by the particular
statically linked Oodle version. This avoids differences in parameter count,
ordering, and enum values between Oodle versions.

At minimum, verify the wrapper function by doing the following:

- Save a stable sequence of bytes from the function prologue as a signature.
- Use the module base address plus an RVA instead of hard-coding an absolute
  runtime address.
- Compare the signature again immediately before calling the function.
- Verify the compressed-stream prefix, input size, and output size.
- Explicitly specify integer or pointer types for every Cheat Engine argument.
- Set a reasonable timeout.
- Require the return value to exactly match the expected decompressed size.

Do not treat `0xCECECECECECECECE` as a decompression result. It generally means
that the target code never wrote to Cheat Engine's result slot, for example
because thread hijacking timed out or the call did not complete.

## 7. Cheat Engine Lua call framework

The general framework is shown below. The paths, offsets, sizes, RVA, and
signature must be filled in for the specific executable:

```lua
local module_base = getAddressSafe("Game.exe")
local wrapper = module_base + WRAPPER_RVA

-- Verify the wrapper's machine-code signature and the input stream prefix
-- before making the call.
local input_buffer = allocateMemory(COMPRESSED_SIZE)
local output_buffer = allocateMemory(OUTPUT_SIZE)
writeBytes(input_buffer, compressed_bytes)

local function int_arg(value)
    return { type = 0, value = value }
end

local result = executeCodeEx(
    0, 10000, wrapper,
    int_arg(input_buffer), int_arg(COMPRESSED_SIZE),
    int_arg(output_buffer), int_arg(OUTPUT_SIZE)
)

if result ~= OUTPUT_SIZE then
    error("decode failed: " .. tostring(result))
end

local output = readBytes(output_buffer, OUTPUT_SIZE, true)
```

Prefer a wrapper that the game already uses. Do not directly call an
underlying 14- or 15-parameter entry point unless its actual signature has
been fully recovered from local call sites.

## 8. Compare original and override assets

After decompressing the original chunk, compare it with the uncompressed chunk
from the override container:

1. Calculate their common prefix and common suffix.
2. Compare the string tables to confirm that both files represent the same
   asset and set of fields.
3. Align insertions and deletions in the differing middle section; do not rely
   only on comparing bytes at identical file offsets.
4. Identify common numeric encodings:
   - 32-bit little-endian integers;
   - 32-bit IEEE 754 floating-point values;
   - 64-bit IEEE 754 double-precision values;
   - Unreal variable-length integers, Name Index values, and zero masks.
5. Remember that unversioned property serialization may omit zero values. If
   the original file is shorter than the override, it does not necessarily
   mean a field was added; a previously zero-valued field may now need to be
   serialized explicitly.

A numeric candidate must satisfy all of the following conditions:

- The byte order is correct.
- The value is within a reasonable range.
- The surrounding structures realign after the value.
- All data other than the target value remains unchanged.

## 9. Fixed-length in-place modification

If the target value is stored at a fixed location in the override `.ucas`, it
can be replaced in place:

1. Verify the old value at the target offset.
2. Encode the new value using the same type and length.
3. Overwrite only the target bytes.
4. Read the value back and verify it.
5. Compare the files before and after modification to ensure that only the
   expected bytes changed.
6. Install the `.pak` and `.utoc` together with the modified `.ucas`.

As long as the chunk length, offsets, and compression state remain unchanged,
the TOC generally does not need to be modified. This approach cannot be relied
upon if the container uses signatures or runtime hash verification.

## 10. When the container must be rebuilt

Rebuild the container with a proper packaging tool instead of applying an
in-place patch if any of the following conditions apply:

- The new value changes the serialized length.
- Properties are added or removed.
- The set of compression blocks spanned by the chunk changes.
- A directory, filename, or Mount Point is changed.
- The modified data needs to be recompressed.
- Container signing or mandatory integrity verification is enabled.
- A game update changes the asset schema.

When rebuilding, update the chunk lengths, physical offsets, compression-block
table, directory index, container header, and any required hashes or
signatures together.

## 11. Safety and verification

- Reconfirm the RVA and signature for every executable version.
- Save your progress and remain at the main menu before invoking game code.
- For the first test, decompress only one small, known chunk.
- Stop immediately if a call times out, a signature does not match, or the
  returned size is unexpected.
- Do not experiment directly in the game directory. Generate a complete set of
  same-named files in a separate directory first.
- Close the game before installation and keep backups of the original files.
- After making a change, verify loading and logs before playing for an extended
  period.
