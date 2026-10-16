/* SPDX-License-Identifier: GPL-3.0-or-later
 * Micropolis C API. See MicropolisGPLLicenseNotice.md for EA additional terms.
 * Copyright (C) 1989 - 2007 Electronic Arts Inc. (underlying engine).
 *
 * ABI version 1. All functions use caller-owned buffers and UTF-8 paths.
 * A successful create transfers one owned handle to the caller; destroy it once.
 * NULL is accepted by destroy; stale handles/double destruction are invalid.
 * Operations on one live handle are serialized internally. Destruction must be
 * synchronized externally with every call. Different handles are independent.
 * No C++ exception crosses this header. State is polled; no callback/reentrancy.
 * A failed allocation during a mutating operation may partially change that
 * handle; destroy/recreate it after MP_OUT_OF_MEMORY or MP_INTERNAL_ERROR.
 */
#ifndef MICROPOLIS_NATIVE_H
#define MICROPOLIS_NATIVE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#define MP_ABI_VERSION 1
#define MP_MAP_WIDTH 120
#define MP_MAP_HEIGHT 100
#define MP_TILE_COUNT (MP_MAP_WIDTH * MP_MAP_HEIGHT)

typedef struct MPGame MPGame;
typedef int32_t MPResult;
enum {
    MP_OK = 0, MP_INVALID_ARGUMENT = 1, MP_BUFFER_TOO_SMALL = 2,
    MP_OUT_OF_MEMORY = 3, MP_IO_ERROR = 4, MP_CANNOT_BUILD = 5,
    MP_NO_FUNDS = 6, MP_NEEDS_BULLDOZE = 7, MP_INTERNAL_ERROR = 8
};
typedef int32_t MPTool;
enum {
    MP_TOOL_ROAD = 1, MP_TOOL_RESIDENTIAL = 2, MP_TOOL_COMMERCIAL = 3,
    MP_TOOL_INDUSTRIAL = 4, MP_TOOL_BULLDOZER = 5, MP_TOOL_WIRE = 6,
    MP_TOOL_RAILROAD = 7, MP_TOOL_PARK = 8, MP_TOOL_COAL_POWER = 9
};
typedef struct MPSnapshot {
    int64_t city_time;
    int64_t funds;
    int64_t population;
    uint64_t revision; /* conservative mutation counter, not a saved field */
    int32_t speed;     /* requested speed 0..3, retained while paused */
    int32_t paused;    /* 0 or 1 */
    int32_t year;
    int32_t month;     /* 0..11 */
    float police_fraction;
    float fire_fraction;
    float road_fraction;
} MPSnapshot;

/* Error strings are immutable static storage; never free them. */
const char *mp_result_string(MPResult result);
MPResult mp_create(MPGame **out_game); /* initializes an empty, funded city */
void mp_destroy(MPGame *game);
/* Resets the city and runtime state to defaults, then generates this seed. */
MPResult mp_generate(MPGame *game, int32_t seed);
/* At most 1,000,000 ticks per call. A tick is an engine update, not a month. */
MPResult mp_step(MPGame *game, uint32_t ticks);
MPResult mp_set_paused(MPGame *game, int32_t paused);
MPResult mp_set_speed(MPGame *game, int32_t speed);
MPResult mp_set_funding(MPGame *game, float police, float fire, float road);
MPResult mp_get_snapshot(MPGame *game, MPSnapshot *out_snapshot);
/* Copies full raw 16-bit tiles (including flags), row-major: y*120+x.
 * capacity is an element count, not bytes. No writes on a too-small buffer.
 * mop selects the auxiliary tileset map when 1; main simulation map when 0. */
MPResult mp_copy_map(MPGame *game, int32_t mop, uint16_t *out_tiles, size_t capacity);
/* Coordinates are map tiles, zones are centered on (x,y). Engine validates the
 * footprint and funds. A rejected tool does not charge or change the map. */
MPResult mp_build(MPGame *game, MPTool tool, int32_t x, int32_t y);
/* Accepts classic 27120-byte or map+mop 51120-byte .cty files. Failed load
 * preserves the previous city. A successful load resets speed to 3/unpaused,
 * following the legacy loader. Loading/generation resets runtime-only state. */
MPResult mp_load_city(MPGame *game, const char *utf8_path);
/* Writes the compatible map+mop format via a temporary sibling and rename.
 * An I/O failure preserves an existing destination. No resources are bundled.
 * This is atomic replacement, not a guarantee of power-loss durability.
 * The application must acquire sandbox/security-scoped URL access first. */
MPResult mp_save_city(MPGame *game, const char *utf8_path);
#ifdef __cplusplus
}
#endif
#endif
