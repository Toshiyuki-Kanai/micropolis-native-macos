/* fileio.cpp
 *
 * Micropolis, Unix Version.  This game was released for the Unix platform
 * in or about 1990 and has been modified for inclusion in the One Laptop
 * Per Child program.  Copyright (C) 1989 - 2007 Electronic Arts Inc.  If
 * you need assistance with this program, you may contact:
 *   http://wiki.laptop.org/go/Micropolis  or email  micropolis@laptop.org.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.  You should have received a
 * copy of the GNU General Public License along with this program.  If
 * not, see <http://www.gnu.org/licenses/>.
 *
 *             ADDITIONAL TERMS per GNU GPL Section 7
 *
 * No trademark or publicity rights are granted.  This license does NOT
 * give you any right, title or interest in the trademark SimCity or any
 * other Electronic Arts trademark.  You may not distribute any
 * modification of this program using the trademark SimCity or claim any
 * affliation or association with Electronic Arts Inc. or its employees.
 *
 * Any propagation or conveyance of this program must include this
 * copyright notice and these terms.
 *
 * If you convey this program (or any modifications of it) and assume
 * contractual liability for the program to recipients of it, you agree
 * to indemnify Electronic Arts for any liability that those contractual
 * assumptions impose on Electronic Arts.
 *
 * You may not misrepresent the origins of this program; modified
 * versions of the program must be marked as such and not identified as
 * the original program.
 *
 * This disclaimer supplements the one included in the General Public
 * License.  TO THE FULLEST EXTENT PERMISSIBLE UNDER APPLICABLE LAW, THIS
 * PROGRAM IS PROVIDED TO YOU "AS IS," WITH ALL FAULTS, WITHOUT WARRANTY
 * OF ANY KIND, AND YOUR USE IS AT YOUR SOLE RISK.  THE ENTIRE RISK OF
 * SATISFACTORY QUALITY AND PERFORMANCE RESIDES WITH YOU.  ELECTRONIC ARTS
 * DISCLAIMS ANY AND ALL EXPRESS, IMPLIED OR STATUTORY WARRANTIES,
 * INCLUDING IMPLIED WARRANTIES OF MERCHANTABILITY, SATISFACTORY QUALITY,
 * FITNESS FOR A PARTICULAR PURPOSE, NONINFRINGEMENT OF THIRD PARTY
 * RIGHTS, AND WARRANTIES (IF ANY) ARISING FROM A COURSE OF DEALING,
 * USAGE, OR TRADE PRACTICE.  ELECTRONIC ARTS DOES NOT WARRANT AGAINST
 * INTERFERENCE WITH YOUR ENJOYMENT OF THE PROGRAM; THAT THE PROGRAM WILL
 * MEET YOUR REQUIREMENTS; THAT OPERATION OF THE PROGRAM WILL BE
 * UNINTERRUPTED OR ERROR-FREE, OR THAT THE PROGRAM WILL BE COMPATIBLE
 * WITH THIRD PARTY SOFTWARE OR THAT ANY ERRORS IN THE PROGRAM WILL BE
 * CORRECTED.  NO ORAL OR WRITTEN ADVICE PROVIDED BY ELECTRONIC ARTS OR
 * ANY AUTHORIZED REPRESENTATIVE SHALL CREATE A WARRANTY.  SOME
 * JURISDICTIONS DO NOT ALLOW THE EXCLUSION OF OR LIMITATIONS ON IMPLIED
 * WARRANTIES OR THE LIMITATIONS ON THE APPLICABLE STATUTORY RIGHTS OF A
 * CONSUMER, SO SOME OR ALL OF THE ABOVE EXCLUSIONS AND LIMITATIONS MAY
 * NOT APPLY TO YOU.
 */

/** 
 * @file fileio.cpp
 * @brief File I/O operations for Micropolis game engine.
 *
 * Implements file loading and saving functionalities for the
 * Micropolis game engine. It includes endianess conversions for data
 * compatibility between different architectures, loading and saving
 * city files, handling scenario files, and various utility functions
 * to support file I/O operations. It also includes functions to
 * report file operations to the front-end.
 */


////////////////////////////////////////////////////////////////////////


#include "micropolis.h"


////////////////////////////////////////////////////////////////////////

/*
 * Classic SimCity/Micropolis save files are big-endian on disk.
 *
 * The original game came from Macintosh/Motorola systems, and the file format
 * remains a stream of big-endian 16-bit words. Runtime memory may be big-endian
 * or little-endian depending on the target. WebAssembly is specified to use
 * little-endian linear memory, so Emscripten/WASM correctly takes the
 * little-endian branch below. This is not pretending to be a different CPU; it
 * is compiling to a virtual architecture whose memory byte order is defined.
 *
 * Boundary rule:
 *   file bytes:    big-endian 16-bit words
 *   host memory:   target-dependent; WASM/x86/ARM64 are little-endian here
 *   load/save:     convert explicitly at this file boundary
 */


// Modified 2026-10-16: explicit big-endian words and signed 32-bit fields.
// Never alias short arrays as long/Quad: long is 64-bit on macOS/Linux LP64.
#include <cstdint>
#include <cmath>
#include <vector>
#include <memory>

static_assert(sizeof(short) == 2, "The classic city format requires 16-bit shorts");
struct CityFileCloser {
    void operator()(FILE *file) const noexcept { fclose(file); }
};

static int32_t read_city_int(const short *words)
{
    uint32_t bits = (uint32_t(uint16_t(words[0])) << 16) | uint16_t(words[1]);
    // Arithmetic conversion also defines negative fields without type punning.
    return bits <= INT32_MAX ? int32_t(bits)
                            : int32_t(int64_t(bits) - (int64_t(1) << 32));
}

static void write_city_int(short *words, int32_t value)
{
    uint32_t bits = uint32_t(value);
    uint16_t hi = uint16_t(bits >> 16), lo = uint16_t(bits);
    words[0] = hi <= INT16_MAX ? short(hi) : short(int(hi) - 65536);
    words[1] = lo <= INT16_MAX ? short(lo) : short(int(lo) - 65536);
}

// Write bytes without modifying live arrays, including on short writes.
static bool save_short(const short *buf, int len, FILE *f)
{
    for (int i = 0; i < len; ++i) {
        uint16_t word = uint16_t(buf[i]);
        unsigned char bytes[2] = {static_cast<unsigned char>(word >> 8),
                                  static_cast<unsigned char>(word)};
        if (fwrite(bytes, 1, 2, f) != 2) return false;
    }
    return true;
}

/**
 * Load a city file from a given filename and (optionally) directory.
 * @param filename Name of the file to load.
 * @param dir      If not \c NULL, name of the directory containing the file.
 * @return Load was succesfull.
 */
bool Micropolis::loadFileData(const std::string &filename)
{
    std::unique_ptr<FILE, CityFileCloser> file(fopen(filename.c_str(), "rb"));
    FILE *f = file.get();
    if (!f) return false;
    const size_t historyBytes = 6 * HISTORY_LENGTH + MISC_HISTORY_LENGTH;
    const size_t mapBytes = WORLD_W * WORLD_H * 2;
    if (fseek(f, 0, SEEK_END) != 0) return false;
    long size = ftell(f);
    if (size != long(historyBytes + mapBytes) &&
        size != long(historyBytes + 2 * mapBytes)) return false;
    if (fseek(f, 0, SEEK_SET) != 0) return false;
    std::vector<unsigned char> bytes(static_cast<size_t>(size));
    bool ok = fread(bytes.data(), 1, bytes.size(), f) == bytes.size();
    ok = fclose(file.release()) == 0 && ok;
    if (!ok) return false;

    size_t offset = 0;
    auto readWords = [&](auto *out, size_t count) {
        for (size_t i = 0; i < count; ++i) {
            uint16_t word = (uint16_t(bytes[offset]) << 8) | bytes[offset + 1];
            offset += 2;
            // Signed histories preserve the exact 16-bit representation.
            int value = word <= INT16_MAX ? int(word) : int(word) - 65536;
            out[i] = value;
        }
    };
    for (short *hist : {resHist, comHist, indHist, crimeHist, pollutionHist, moneyHist})
        readWords(hist, HISTORY_LENGTH / 2);
    readWords(miscHist, MISC_HISTORY_LENGTH / 2);
    readWords(mapBase, WORLD_W * WORLD_H);
    if (bytes.size() == historyBytes + 2 * mapBytes) readWords(mopBase, WORLD_W * WORLD_H);
    else memset(mopBase, 0, mapBytes);
    return true;
}

/**
 * Load a file, and initialize the game variables.
 * @param filename Name of the file to load.
 * @return Load was succesfull.
 */
bool Micropolis::loadFile(const std::string &filename)
{
    if (!loadFileData(filename)) return false;

    setFunds(read_city_int(miscHist + 50));
    cityTime = read_city_int(miscHist + 8);

    setAutoBulldoze(miscHist[52] != 0);   // flag for autoBulldoze
    setAutoBudget(miscHist[53] != 0);     // flag for autoBudget
    setAutoGoto(miscHist[54] != 0);       // flag for auto-goto
    setEnableSound(miscHist[55] != 0);    // flag for the sound on/off
    setCityTax(miscHist[56]);
    //setSpeed(miscHist[57]);
    setSpeed(3); // Naw let's reset the speed to 3 after loading a city.
    changeCensus();
    mustUpdateOptions = true;

    // Reset transient budget values first, then restore the stored fractions.
    initFundingLevel();
    policePercent = clamp(read_city_int(miscHist + 58), int32_t(0), int32_t(65536)) / 65536.0f;
    firePercent = clamp(read_city_int(miscHist + 60), int32_t(0), int32_t(65536)) / 65536.0f;
    roadPercent = clamp(read_city_int(miscHist + 62), int32_t(0), int32_t(65536)) / 65536.0f;

    cityTime = max((Quad)0, cityTime);

    // If the tax is nonsensical, set it to a reasonable value.
    if (cityTax > 20 || cityTax < 0) {
        setCityTax(7);
    }

    // If the speed is nonsensical, set it to a reasonable value.
    if (simSpeed < 0 || simSpeed > 3) {
        simSpeed = 3;
    }

    setSpeed(simSpeed);
    setPasses(1);

    // Set the scenario id to 0.
    initWillStuff();
    scenario = SC_NONE;
    initSimLoad = 1;
    doInitialEval = false;
    doSimInit();
    invalidateMaps();

    return true;
}


/**
 * Save a game to disk.
 * @param filename Name of the file to use for storing the game.
 * @return The game was saved successfully.
 */
bool Micropolis::saveFile(const std::string &filename)
{
    // The on-disk fields are signed 32-bit, regardless of the host ABI.
    if (totalFunds < INT32_MIN || totalFunds > INT32_MAX ||
        cityTime < INT32_MIN || cityTime > INT32_MAX ||
        !std::isfinite(policePercent) || !std::isfinite(firePercent) ||
        !std::isfinite(roadPercent)) return false;
    FILE *f = fopen(filename.c_str(), "wb");
    if (!f) return false;

    write_city_int(miscHist + 50, int32_t(totalFunds));
    write_city_int(miscHist + 8, int32_t(cityTime));

    miscHist[52] = autoBulldoze;   // flag for autoBulldoze
    miscHist[53] = autoBudget;     // flag for autoBudget
    miscHist[54] = autoGoto;       // flag for auto-goto
    miscHist[55] = enableSound;    // flag for the sound on/off
    miscHist[57] = simSpeed;
    miscHist[56] = cityTax;        /* post release */

    write_city_int(miscHist + 58, int32_t(clamp(policePercent, 0.0f, 1.0f) * 65536));
    write_city_int(miscHist + 60, int32_t(clamp(firePercent, 0.0f, 1.0f) * 65536));
    write_city_int(miscHist + 62, int32_t(clamp(roadPercent, 0.0f, 1.0f) * 65536));

    bool result =
        save_short(resHist, HISTORY_LENGTH / 2, f) &&
        save_short(comHist, HISTORY_LENGTH / 2, f) &&
        save_short(indHist, HISTORY_LENGTH / 2, f) &&
        save_short(crimeHist, HISTORY_LENGTH / 2, f) &&
        save_short(pollutionHist, HISTORY_LENGTH / 2, f) &&
        save_short(moneyHist, HISTORY_LENGTH / 2, f) &&
        save_short(miscHist, MISC_HISTORY_LENGTH / 2, f) &&
        /*
         * Save the map in the engine's native linear order: map[x][y] with
         * linear index x * WORLD_H + y. This is column-major relative to city
         * coordinates, and is the same order exposed to JavaScript/WASM tools.
         */
        save_short(((short *)&map[0][0]), WORLD_W * WORLD_H, f) &&
        save_short(((short *)&mop[0][0]), WORLD_W * WORLD_H, f);

    return fclose(f) == 0 && result;
}


/**
 * Load a scenario.
 * @param s Scenario to load.
 * @note \a s cannot be \c SC_NONE.
 */
void Micropolis::loadScenario(Scenario s)
{
    std::string name;
    std::string fname;

    cityFileName = "";

    setGameLevel(LEVEL_EASY);

    if (s < SC_DULLSVILLE || s > SC_RIO) {
        s = SC_DULLSVILLE;
    }

    switch (s) {
        case SC_DULLSVILLE:
            name = "Dullsville";
            fname = "cities/scenario_dullsville.cty";
            scenario = SC_DULLSVILLE;
            cityTime = ((1900 - 1900) * 48) + 2;
            setFunds(5000);
            break;
        case SC_SAN_FRANCISCO:
            name = "San Francisco";
            fname = "cities/scenario_san_francisco.cty";
            scenario = SC_SAN_FRANCISCO;
            cityTime = ((1906 - 1900) * 48) + 2;
            setFunds(20000);
            break;
        case SC_HAMBURG:
            name = "Hamburg";
            fname = "cities/scenario_hamburg.cty";
            scenario = SC_HAMBURG;
            cityTime = ((1944 - 1900) * 48) + 2;
            setFunds(20000);
            break;
        case SC_BERN:
            name = "Bern";
            fname = "cities/scenario_bern.cty";
            scenario = SC_BERN;
            cityTime = ((1965 - 1900) * 48) + 2;
            setFunds(20000);
            break;
        case SC_TOKYO:
            name = "Tokyo";
            fname = "cities/scenario_tokyo.cty";
            scenario = SC_TOKYO;
            cityTime = ((1957 - 1900) * 48) + 2;
            setFunds(20000);
            break;
        case SC_DETROIT:
            name = "Detroit";
            fname = "cities/scenario_detroit.cty";
            scenario = SC_DETROIT;
            cityTime = ((1972 - 1900) * 48) + 2;
            setFunds(20000);
            break;
        case SC_BOSTON:
            name = "Boston";
            fname = "cities/scenario_boston.cty";
            scenario = SC_BOSTON;
            cityTime = ((2010 - 1900) * 48) + 2;
            setFunds(20000);
            break;
        case SC_RIO:
            name = "Rio de Janeiro";
            fname = "cities/scenario_rio_de_janeiro.cty";
            scenario = SC_RIO;
            cityTime = ((2047 - 1900) * 48) + 2;
            setFunds(20000);
            break;
        default:
            NOT_REACHED();
            break;
    }

    setCleanCityName(name);
    setSpeed(3);
    setCityTax(7);

    loadFileData(fname);

    initWillStuff();
    initFundingLevel();
    updateFunds();
    invalidateMaps();
    initSimLoad = 1;
    doInitialEval = false;
    doSimInit();
    didLoadScenario(s, name, fname);
}


/** Report to the front-end that the scenario was loaded. */
void Micropolis::didLoadScenario(int s, const std::string name, const std::string fname)
{
    callback->didLoadScenario(this, callbackVal, name, fname);
}

/**
 * Try to load a new game from disk.
 * @param filename Name of the file to load.
 * @return Game was loaded successfully.
 * @todo In what state is the game left when loading fails?
 * @todo String normalization code is duplicated in Micropolis::saveCityAs().
 *       Extract to a sub-function.
 * @bug Function fails if \c lastDot<lastSlash (ie with \c "x.y/bla" )
 */
bool Micropolis::loadCity(const std::string &filename)
{
    if (loadFile(filename)) {

        cityFileName = filename;

        size_t lastSlash = cityFileName.find_last_of('/');
        size_t pos = (lastSlash == std::string::npos) ? 0 : lastSlash + 1;

        size_t lastDot = cityFileName.find_last_of('.');
        size_t last =
            (lastDot == std::string::npos) ? cityFileName.length() : lastDot;

        std::string newCityName = cityFileName.substr(pos, last - pos);
        setCityName(newCityName);

        doSimInit();

        didLoadCity(filename);

        return true;

    } else {

        didntLoadCity(filename);

        return false;

    }
}

/** Report to the frontend that the game was successfully loaded. */
void Micropolis::didLoadCity(const std::string &filename)
{
    callback->didLoadCity(this, callbackVal, filename);
}


/**
 * Report to the frontend that the game failed to load.
 * @param msg File that attempted to load
 */
void Micropolis::didntLoadCity(const std::string &filename)
{
    callback->didntLoadCity(this, callbackVal, filename);
}


/**
 * Try to save the game.
 * @todo This is a no-op if the Micropolis::cityFileName is empty.
 *       In that case, we should probably warn the user about the failure.
 */
void Micropolis::saveCity()
{
    if (cityFileName.length() > 0) {

        doSaveCityAs(cityFileName);

    } else {
        if (saveFile(cityFileName)) {

            didSaveCity(cityFileName);

        } else {

            didntSaveCity(cityFileName);

        }
    }
}


/**
 * Report to the frontend that the city is being saved.
 * @param filename Name of the file used
 */
void Micropolis::doSaveCityAs(const std::string &filename)
{
    callback->saveCityAs(this, callbackVal, filename);
}


/**
 * Report to the frontend that the city was saved successfully.
 * @param filename Name of the file used
 */
void Micropolis::didSaveCity(const std::string &filename)
{
    callback->didSaveCity(this, callbackVal, filename);
}


/**
 * Report to the frontend that the city could not be saved.
 * @param filename Name of the file used
 */
void Micropolis::didntSaveCity(const std::string &filename)
{
    callback->didntSaveCity(this, callbackVal, filename);
}


/**
 * Save the city under a new name (?)
 * @param filename Name of the file to use for storing the game.
 * @todo String normalization code is duplicated in Micropolis::loadCity().
 *       Extract to a sub-function.
 * @bug Function fails if \c lastDot<lastSlash (ie with \c "x.y/bla" )
 */
void Micropolis::saveCityAs(const std::string &filename)
{
    cityFileName = filename;

    if (saveFile(cityFileName)) {

        size_t lastDot = cityFileName.find_last_of('.');
        size_t lastSlash = cityFileName.find_last_of('/');

        size_t pos =
            (lastSlash == std::string::npos) ? 0 : lastSlash + 1;
        size_t last =
            (lastDot == std::string::npos) ? cityFileName.length() : lastDot;
        size_t len =
            last - pos;
        std::string newCityName =
            cityFileName.substr(pos, len);

        setCityName(newCityName);

        didSaveCity(cityName);

    } else {

        didntSaveCity(cityFileName);

    }
}


////////////////////////////////////////////////////////////////////////
