package io.github.guandor.balatrolite;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.nio.charset.Charset;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

/** Converts the user's fused Balatro executable into a patched LÖVE archive. */
final class BalatroPatcher {
    interface ProgressListener {
        void onProgress(String message);
    }

    static final class PatchException extends Exception {
        PatchException(String message) {
            super(message);
        }

        PatchException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    private static final int BUFFER_SIZE = 64 * 1024;
    private static final int MAX_PATCH_TEXT_SIZE = 4 * 1024 * 1024;
    private static final long MAX_ARCHIVE_SIZE = 512L * 1024L * 1024L;
    private static final Charset UTF_8 = Charset.forName("UTF-8");

    private static final Set<String> REQUIRED_ENTRIES = new HashSet<>(Arrays.asList(
        "main.lua",
        "globals.lua",
        "game.lua",
        "cardarea.lua",
        "engine/text.lua",
        "functions/button_callbacks.lua",
        "conf.lua",
        "resources/shaders/CRT.fs",
        "resources/shaders/background.fs",
        "resources/shaders/flame.fs"
    ));

    private BalatroPatcher() {}

    /**
     * Removes the Windows executable prefix from a fused .exe, producing a normal
     * ZIP-compatible .love file. A .love input is copied through the same path.
     */
    static void normalizeGameArchive(File selectedFile, File outputFile)
        throws PatchException {
        if (selectedFile.length() <= 0 || selectedFile.length() > MAX_ARCHIVE_SIZE) {
            throw new PatchException("The selected file is empty or unexpectedly large.");
        }

        try {
            long archiveOffset = findArchiveOffset(selectedFile);
            try (FileInputStream input = new FileInputStream(selectedFile);
                 OutputStream output = new BufferedOutputStream(new FileOutputStream(outputFile))) {
                skipFully(input, archiveOffset);
                copy(input, output);
            }

            try (ZipFile archive = new ZipFile(outputFile)) {
                for (String required : REQUIRED_ENTRIES) {
                    if (archive.getEntry(required) == null) {
                        throw new PatchException(
                            "This does not look like the supported Balatro 1.0.1o game file " +
                            "(missing " + required + ")."
                        );
                    }
                }
            }
        } catch (PatchException error) {
            deleteQuietly(outputFile);
            throw error;
        } catch (IOException error) {
            deleteQuietly(outputFile);
            throw new PatchException("Could not read the selected Balatro file.", error);
        }
    }

    static void patchGame(
        File sourceLove,
        File outputLove,
        byte[] smallScreenPatch,
        byte[] optionsPatch,
        byte[] controlsPatch,
        byte[] performancePatch,
        byte[] nunitoFont,
        boolean smallLayout,
        boolean performanceOptimizations,
        ProgressListener progress
    ) throws PatchException {
        Set<String> seen = new HashSet<>();
        File temporary = new File(outputLove.getParentFile(), outputLove.getName() + ".tmp");
        deleteQuietly(temporary);

        try (ZipInputStream input = new ZipInputStream(
                 new BufferedInputStream(new FileInputStream(sourceLove)));
             ZipOutputStream output = new ZipOutputStream(
                 new BufferedOutputStream(new FileOutputStream(temporary)))) {
            ZipEntry entry;
            while ((entry = input.getNextEntry()) != null) {
                String name = entry.getName().replace('\\', '/');
                validateEntryName(name);
                if (!seen.add(name)) {
                    throw new PatchException("The game archive contains a duplicate entry: " + name);
                }

                // These are supplied by Balatro Lite below, so omit any stale copies.
                if (name.equals("portmaster/small_screen.lua") ||
                    name.equals("portmaster/options.lua") ||
                    name.equals("portmaster/controls.lua") ||
                    name.equals("portmaster/pm_android_config.lua") ||
                    name.equals("portmaster/perf.lua") ||
                    (smallLayout && name.equals("resources/fonts/m6x11plus.ttf"))) {
                    input.closeEntry();
                    continue;
                }

                ZipEntry patchedEntry = copyMetadata(entry, name);
                output.putNextEntry(patchedEntry);
                if (!entry.isDirectory()) {
                    if (isPatchTarget(name)) {
                        byte[] data = readBounded(input, MAX_PATCH_TEXT_SIZE, name);
                        byte[] patched = patchTextFile(
                            name, data, smallLayout, performanceOptimizations);
                        output.write(patched);
                    } else {
                        copy(input, output);
                    }
                }
                output.closeEntry();
                input.closeEntry();
            }

            for (String required : REQUIRED_ENTRIES) {
                if (!seen.contains(required)) {
                    throw new PatchException("The game archive changed unexpectedly (missing " + required + ").");
                }
            }

            progress.onProgress("Adding the selected port settings…");
            addBytes(output, "portmaster/options.lua", optionsPatch);
            addBytes(output, "portmaster/controls.lua", controlsPatch);
            addBytes(
                output,
                "portmaster/pm_android_config.lua",
                ("G.BALATRO_PM_PERF_OPTIMIZATIONS = " +
                    (performanceOptimizations ? "true\n" : "false\n")).getBytes(UTF_8)
            );
            addBytes(output, "portmaster/perf.lua", performancePatch);
            if (smallLayout) {
                addBytes(output, "portmaster/small_screen.lua", smallScreenPatch);
                addBytes(output, "resources/fonts/m6x11plus.ttf", nunitoFont);
            }
        } catch (PatchException error) {
            deleteQuietly(temporary);
            throw error;
        } catch (IOException error) {
            deleteQuietly(temporary);
            throw new PatchException("Could not build the patched game archive.", error);
        }

        try (ZipFile result = new ZipFile(temporary)) {
            if (result.getEntry("portmaster/options.lua") == null ||
                result.getEntry("portmaster/controls.lua") == null ||
                result.getEntry("portmaster/pm_android_config.lua") == null ||
                result.getEntry("portmaster/perf.lua") == null ||
                (smallLayout && (result.getEntry("portmaster/small_screen.lua") == null ||
                    result.getEntry("resources/fonts/m6x11plus.ttf") == null))) {
                throw new PatchException("The completed game archive failed verification.");
            }
        } catch (IOException error) {
            deleteQuietly(temporary);
            throw new PatchException("The completed game archive failed verification.", error);
        }

        replaceFile(temporary, outputLove);
    }

    private static boolean isPatchTarget(String name) {
        return REQUIRED_ENTRIES.contains(name);
    }

    private static byte[] patchTextFile(
        String name,
        byte[] data,
        boolean smallLayout,
        boolean performanceOptimizations
    ) throws PatchException {
        // The purchased Windows archive uses CRLF in some shaders and LF in its
        // Lua files. Normalize patch targets so the checks are platform-neutral.
        String text = new String(data, UTF_8).replace("\r\n", "\n");
        switch (name) {
            case "globals.lua":
                text = replaceLineContainingExactly(
                    text,
                    "loadstring(",
                    "    -- Android compatibility: the user imported this licensed archive.\n" +
                    "    if love.system.getOS() == 'Android' or love.system.getOS() == 'iOS' then\n" +
                    "        self.F_SAVE_TIMER = 5\n" +
                    "        self.F_DISCORD = true\n" +
                    "        self.F_NO_ACHIEVEMENTS = true\n" +
                    "        self.F_CRASH_REPORTS = false\n" +
                    "        self.F_SOUND_THREAD = true\n" +
                    "        self.F_VIDEO_SETTINGS = false\n" +
                    "        self.F_ENGLISH_ONLY = false\n" +
                    "        self.F_QUIT_BUTTON = false\n" +
                    "    end",
                    name
                );
                if (performanceOptimizations) {
                    text = replaceExactly(text, "crt = 70,", "crt = 0,", 1, name);
                    text = replaceExactly(text, "bloom = 1", "bloom = 0", 1, name);
                    text = replaceExactly(text, "shadows = 'On'", "shadows = 'Off'", 1, name);
                }
                break;

            case "main.lua":
                text = replaceExactly(
                    text,
                    "require \"challenges\"",
                    "require \"challenges\"\n" +
                        "require \"portmaster/options\"\n" +
                        "require \"portmaster/controls\"\n" +
                        "require \"portmaster/pm_android_config\"\n" +
                        (smallLayout ? "require \"portmaster/small_screen\"\n" : "") +
                        "require \"portmaster/perf\"",
                    1,
                    name
                );
                break;

            case "functions/button_callbacks.lua":
                text = replaceExactly(
                    text,
                    "if G.CONTROLLER.text_input_hook == e and G.CONTROLLER.HID.controller then",
                    "if G.CONTROLLER.text_input_hook == e and " +
                        "(G.CONTROLLER.HID.controller or G.CONTROLLER.HID.touch) then",
                    1,
                    name
                );
                text = replaceExactly(
                    text,
                    "resizable = true,",
                    "resizable = not (love.system.getOS() == 'Android' or " +
                        "love.system.getOS() == 'iOS'),",
                    1,
                    name
                );
                text = replaceExactly(
                    text,
                    "highdpi = (love.system.getOS() == 'OS X')",
                    "highdpi = (love.system.getOS() == 'OS X' or " +
                        "love.system.getOS() == 'Android' or love.system.getOS() == 'iOS')",
                    1,
                    name
                );
                break;

            case "conf.lua":
                text = replaceExactly(
                    text,
                    "t.window.width = 0",
                    "t.identity = 'balatro-lite'\n" +
                        "\tt.externalstorage = true\n" +
                        "\tt.window.width = 0\n\tt.window.usedpiscale = false",
                    1,
                    name
                );
                break;

            case "resources/shaders/flame.fs":
                text = replaceExactly(
                    text,
                    "#endif",
                    "#endif\n#ifdef GL_ES\n\tprecision MY_HIGHP_OR_MEDIUMP float;\n#endif",
                    1,
                    name
                );
                text = replaceExactly(
                    text,
                    "vec4 effect( vec4 colour, Image texture, vec2 texture_coords, vec2 screen_coords )",
                    "mediump vec4 effect( mediump vec4 colour, Image texture, " +
                        "mediump vec2 texture_coords, mediump vec2 screen_coords )",
                    1,
                    name
                );
                break;

            case "game.lua":
                if (performanceOptimizations) {
                    text = replaceExactly(
                        text,
                        "love.graphics.setShader( G.SHADERS['CRT'])",
                        "if G.SETTINGS.GRAPHICS.crt > 0 then " +
                            "love.graphics.setShader( G.SHADERS['CRT']) else love.graphics.setShader() end",
                        1,
                        name
                    );
                }
                break;

            case "cardarea.lua":
                if (!performanceOptimizations) break;
                text = replaceExactly(
                    text,
                    "(G.SETTINGS.reduced_motion and 0 or 1)*0.02*math.sin(2*G.TIMERS.REAL+card.T.x)",
                    "(G.SETTINGS.reduced_motion and 0 or 0.02*math.sin(2*G.TIMERS.REAL+card.T.x))",
                    4,
                    name
                );
                text = replaceExactly(
                    text,
                    "(G.SETTINGS.reduced_motion and 0 or 1)*0.02*math.sin(2*G.TIMERS.REAL+card.T.x+card.T.y)",
                    "(G.SETTINGS.reduced_motion and 0 or 0.02*math.sin(2*G.TIMERS.REAL+card.T.x+card.T.y))",
                    1,
                    name
                );
                text = replaceExactly(
                    text,
                    "(G.SETTINGS.reduced_motion and 0 or 1)*0.1*math.sin(0.666*G.TIMERS.REAL+card.T.x)",
                    "(G.SETTINGS.reduced_motion and 0 or 0.1*math.sin(0.666*G.TIMERS.REAL+card.T.x))",
                    1,
                    name
                );
                text = replaceExactly(
                    text,
                    "(G.SETTINGS.reduced_motion and 0 or 1)*0.03*math.sin(0.666*G.TIMERS.REAL+card.T.x)",
                    "(G.SETTINGS.reduced_motion and 0 or 0.03*math.sin(0.666*G.TIMERS.REAL+card.T.x))",
                    4,
                    name
                );
                text = replaceExactly(
                    text,
                    "(G.SETTINGS.reduced_motion and 0 or 1)*0.05*math.sin(2*1.666*G.TIMERS.REAL+card.T.x)",
                    "(G.SETTINGS.reduced_motion and 0 or 0.05*math.sin(2*1.666*G.TIMERS.REAL+card.T.x))",
                    1,
                    name
                );
                break;

            case "engine/text.lua":
                if (!performanceOptimizations) break;
                text = replaceExactly(
                    text,
                    "if self.config.quiver then",
                    "if self.config.quiver and not G.SETTINGS.reduced_motion then",
                    1,
                    name
                );
                text = replaceExactly(
                    text,
                    "(G.SETTINGS.reduced_motion and 0 or 1)*0.02*math.sin(2*G.TIMERS.REAL+k)",
                    "(G.SETTINGS.reduced_motion and 0 or 0.02*math.sin(2*G.TIMERS.REAL+k))",
                    1,
                    name
                );
                text = replaceLineContainingExactly(
                    text,
                    "if self.config.float then letter.offset.y =",
                    "        if self.config.float then letter.offset.y = " +
                        "(G.SETTINGS.reduced_motion and 0 or math.sqrt(self.scale)*" +
                        "(2+(self.font.FONTSCALE/G.TILESIZE)*2000*" +
                        "math.sin(2.666*G.TIMERS.REAL+200*k))) + 60*(letter.scale-1) end",
                    name
                );
                text = replaceLineContainingExactly(
                    text,
                    "if self.config.bump then letter.offset.y =",
                    "        if self.config.bump then letter.offset.y = " +
                        "(G.SETTINGS.reduced_motion and 0 or self.bump_amount*" +
                        "math.sqrt(self.scale)*7*math.max(0, (5+self.bump_rate)*" +
                        "math.sin(self.bump_rate*G.TIMERS.REAL+200*k) - 3 - self.bump_rate)) end",
                    name
                );
                break;

            case "resources/shaders/CRT.fs":
                if (!performanceOptimizations) break;
                text = replaceExactly(
                    text,
                    "vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc)\n{",
                    "vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc)\n" +
                        "{ if (crt_intensity <= 0.000001 && noise_fac <= 0.000001 && " +
                        "glitch_intensity <= 0.000001) { MY_HIGHP_OR_MEDIUMP vec2 ftc = " +
                        "(tc*2.0 - vec2(1.0))*scale_fac; ftc += (ftc.yx*ftc.yx)*ftc*" +
                        "(distortion_fac - 1.0); MY_HIGHP_OR_MEDIUMP number fmask = " +
                        "(1.0 - smoothstep(1.0-feather_fac,1.0,abs(ftc.x) - BUFF))*" +
                        "(1.0 - smoothstep(1.0-feather_fac,1.0,abs(ftc.y) - BUFF)); " +
                        "ftc = (ftc + vec2(1.0))/2.0; MY_HIGHP_OR_MEDIUMP vec4 fcol = " +
                        "Texel(tex, ftc); fcol.rgb = (fcol.rgb - vec3(0.55))*1.14 + " +
                        "vec3(0.5); fcol.a = 1.0; return fcol*fmask; }",
                    1,
                    name
                );
                break;

            case "resources/shaders/background.fs":
                if (performanceOptimizations) {
                    text = replaceExactly(text, "i < 5; i++", "i < 2; i++", 1, name);
                }
                break;

            default:
                break;
        }
        return text.getBytes(UTF_8);
    }

    private static String replaceExactly(
        String text,
        String oldValue,
        String newValue,
        int expected,
        String file
    ) throws PatchException {
        int actual = countOccurrences(text, oldValue);
        if (actual != expected) {
            throw new PatchException(
                "Unsupported Balatro version: expected " + expected + " patch location(s) in " +
                file + ", found " + actual + "."
            );
        }
        return text.replace(oldValue, newValue);
    }

    private static String replaceLineContainingExactly(
        String text,
        String needle,
        String replacement,
        String file
    ) throws PatchException {
        int match = text.indexOf(needle);
        if (match < 0 || text.indexOf(needle, match + needle.length()) >= 0) {
            throw new PatchException("Unsupported Balatro version: patch location changed in " + file + ".");
        }
        int start = text.lastIndexOf('\n', match);
        start = start < 0 ? 0 : start + 1;
        int end = text.indexOf('\n', match);
        end = end < 0 ? text.length() : end;
        if (end > start && text.charAt(end - 1) == '\r') {
            end--;
        }
        return text.substring(0, start) + replacement + text.substring(end);
    }

    private static int countOccurrences(String text, String needle) {
        int count = 0;
        int position = 0;
        while ((position = text.indexOf(needle, position)) >= 0) {
            count++;
            position += needle.length();
        }
        return count;
    }

    private static long findArchiveOffset(File file) throws IOException, PatchException {
        try (RandomAccessFile input = new RandomAccessFile(file, "r")) {
            long length = input.length();
            int tailSize = (int) Math.min(length, 22L + 65535L);
            byte[] tail = new byte[tailSize];
            input.seek(length - tailSize);
            input.readFully(tail);

            for (int index = tail.length - 22; index >= 0; index--) {
                if ((tail[index] & 0xff) != 0x50 || (tail[index + 1] & 0xff) != 0x4b ||
                    (tail[index + 2] & 0xff) != 0x05 || (tail[index + 3] & 0xff) != 0x06) {
                    continue;
                }
                int commentLength = littleEndian16(tail, index + 20);
                if (index + 22 + commentLength != tail.length) {
                    continue;
                }
                long centralSize = littleEndian32(tail, index + 12);
                long centralOffset = littleEndian32(tail, index + 16);
                long eocdOffset = length - tailSize + index;
                long archiveOffset = eocdOffset - centralSize - centralOffset;
                if (archiveOffset < 0 || archiveOffset >= length) {
                    continue;
                }
                input.seek(archiveOffset);
                if (input.readUnsignedByte() == 0x50 && input.readUnsignedByte() == 0x4b &&
                    input.readUnsignedByte() == 0x03 && input.readUnsignedByte() == 0x04) {
                    return archiveOffset;
                }
            }
        }
        throw new PatchException("The selected file does not contain a readable Balatro game archive.");
    }

    private static int littleEndian16(byte[] data, int offset) {
        return (data[offset] & 0xff) | ((data[offset + 1] & 0xff) << 8);
    }

    private static long littleEndian32(byte[] data, int offset) {
        return ((long) data[offset] & 0xff) |
            (((long) data[offset + 1] & 0xff) << 8) |
            (((long) data[offset + 2] & 0xff) << 16) |
            (((long) data[offset + 3] & 0xff) << 24);
    }

    private static ZipEntry copyMetadata(ZipEntry source, String name) {
        ZipEntry target = new ZipEntry(name);
        if (source.getTime() >= 0) {
            target.setTime(source.getTime());
        }
        if (source.getComment() != null) {
            target.setComment(source.getComment());
        }
        return target;
    }

    private static void addBytes(ZipOutputStream output, String name, byte[] data)
        throws IOException {
        ZipEntry entry = new ZipEntry(name);
        entry.setTime(0L);
        output.putNextEntry(entry);
        output.write(data);
        output.closeEntry();
    }

    private static byte[] readBounded(InputStream input, int maximum, String name)
        throws IOException, PatchException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[16 * 1024];
        int total = 0;
        int count;
        while ((count = input.read(buffer)) >= 0) {
            total += count;
            if (total > maximum) {
                throw new PatchException("Patch target is unexpectedly large: " + name);
            }
            output.write(buffer, 0, count);
        }
        return output.toByteArray();
    }

    private static void validateEntryName(String name) throws PatchException {
        if (name.startsWith("/") || name.startsWith("../") || name.contains("/../") ||
            name.indexOf('\0') >= 0) {
            throw new PatchException("The selected archive contains an unsafe path.");
        }
    }

    private static void replaceFile(File source, File destination) throws PatchException {
        deleteQuietly(destination);
        if (!source.renameTo(destination)) {
            deleteQuietly(source);
            throw new PatchException("Could not install the completed game archive.");
        }
    }

    private static void skipFully(InputStream input, long bytes) throws IOException {
        long remaining = bytes;
        while (remaining > 0) {
            long skipped = input.skip(remaining);
            if (skipped > 0) {
                remaining -= skipped;
            } else if (input.read() >= 0) {
                remaining--;
            } else {
                throw new IOException("Unexpected end of file");
            }
        }
    }

    private static void copy(InputStream input, OutputStream output) throws IOException {
        byte[] buffer = new byte[BUFFER_SIZE];
        int count;
        while ((count = input.read(buffer)) >= 0) {
            output.write(buffer, 0, count);
        }
    }

    static void deleteQuietly(File file) {
        if (file != null && file.exists()) {
            // All callers pass a single known file inside this app's private directory.
            //noinspection ResultOfMethodCallIgnored
            file.delete();
        }
    }
}
