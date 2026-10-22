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
    MP_NO_FUNDS = 6, MP_NEEDS_BULLDOZE = 7, MP_INTERNAL_ERROR = 8,
    MP_BUDGET_PENDING = 9
};
typedef int32_t MPTool;
enum {
    MP_TOOL_ROAD = 1, MP_TOOL_RESIDENTIAL = 2, MP_TOOL_COMMERCIAL = 3,
    MP_TOOL_INDUSTRIAL = 4, MP_TOOL_BULLDOZER = 5, MP_TOOL_WIRE = 6,
    MP_TOOL_RAILROAD = 7, MP_TOOL_PARK = 8, MP_TOOL_COAL_POWER = 9,
    MP_TOOL_NUCLEAR_POWER = 10, MP_TOOL_POLICE = 11, MP_TOOL_FIRE = 12,
    MP_TOOL_STADIUM = 13, MP_TOOL_SEAPORT = 14, MP_TOOL_AIRPORT = 15
};
/* Additive gameplay API (2026-10-17). MPSnapshot and ABI v1 stay unchanged.
 * Hospitals emerge from residential demand; the engine has no school tool. */
typedef struct MPDetails {
    int64_t tax_income, road_cost, police_cost, fire_cost, assessed_value;
    int32_t tax_rate, score, approval, city_class;
    int32_t powered_zones, unpowered_zones, coal_plants, nuclear_plants;
    int32_t residential_demand, commercial_demand, industrial_demand;
    int32_t pollution, crime, traffic, disasters, auto_budget;
} MPDetails;
enum { MP_DISASTER_FIRE = 1, MP_DISASTER_FLOOD = 2,
       MP_DISASTER_TORNADO = 3, MP_DISASTER_EARTHQUAKE = 4,
       MP_DISASTER_MONSTER = 5, MP_DISASTER_MELTDOWN = 6 };
MPResult mp_get_details(MPGame *game, MPDetails *out_details);
/* Configure tax and allocations without changing automatic/manual mode.
 * Engine clamps funding at the next annual calculation. */
MPResult mp_configure_budget(MPGame *game, int32_t tax_rate,
                             float police, float fire, float road);
MPResult mp_set_disasters(MPGame *game, int32_t enabled);
MPResult mp_trigger_disaster(MPGame *game, int32_t disaster);
/* One visual animation frame using the existing core table; no simulation tick.
 * No-op while paused or at speed zero. Preserves all map status flags. */
MPResult mp_animate_tiles(MPGame *game);
/* Additive inspection API, 2026-10-22. No borrowed storage or ABI changes.
 * Overlay IDs: 0 population, 1 growth, 2 land, 3 crime, 4 pollution,
 * 5 traffic, 6 power, 7 fire coverage, 8 police coverage.
 * Values are expanded to row-major world tiles without changing their units. */
MPResult mp_copy_overlay(MPGame *, int32_t kind, int16_t *, size_t capacity);
/* Six types in residential/commercial/industrial/money/crime/pollution order.
 * Scale 0=10 years, 1=120 years. 120 samples, newest first. */
MPResult mp_copy_history(MPGame *, int32_t type, int32_t scale, int16_t *, size_t capacity);
typedef struct MPPoint { int32_t x, y; } MPPoint;
typedef struct MPEdit { int64_t cost; int32_t placed, rejected; MPResult status; } MPEdit;
/* Tool-only scratch engine copies maps/funds/options/RNG, invokes core doTool.
 * Preview never mutates the live city. Commit is atomic for the whole stroke;
 * any insufficient-funds result leaves live maps/funds/RNG unchanged.
 * Other invalid sites are skipped, as in ordinary tool use. Max 12000 points.
 * Preview tiles (optional) need MP_TILE_COUNT capacity. */
MPResult mp_edit_stroke(MPGame *, MPTool, const MPPoint *, size_t count,
                        int32_t commit, uint16_t *preview, size_t capacity, MPEdit *);
typedef struct MPInspection {
    int32_t category, density, land, crime, pollution, growth, x, y;
} MPInspection;
MPResult mp_inspect(MPGame *, int32_t x, int32_t y, MPInspection *);
typedef struct MPOptions {
    int32_t difficulty, auto_bulldoze, auto_budget, budget_pending;
    int64_t population_delta;
    int32_t score_delta, earthquake_sequence;
    int32_t road_effect, fire_effect, police_effect;
    int32_t problem_ids[4], problem_votes[4];
} MPOptions;
MPResult mp_get_options(MPGame *, MPOptions *);
/* Difficulty 0..2. Setting difficulty alone never resets city funds. */
MPResult mp_set_options(MPGame *, int32_t difficulty, int32_t auto_bulldoze, int32_t auto_budget);
MPResult mp_generate_level(MPGame *, int32_t seed, int32_t difficulty);
/* Accept manual annual budget, then resume explicitly with mp_set_paused.
 * mp_step stops BEFORE core settlement. No simulation accounting is replaced. */
MPResult mp_accept_budget(MPGame *);
typedef struct MPEvent { int32_t message, x, y, important; } MPEvent;
/* Drain at most capacity copied events; bounded queue retains latest 128. */
MPResult mp_poll_events(MPGame *, MPEvent *, size_t capacity, size_t *out_count);
typedef struct MPBudgetQuote {
    int64_t income, road_request, fire_request, police_request;
    int64_t road_funded, fire_funded, police_funded, balance;
} MPBudgetQuote;
/* Execute the core annual phase on a scratch census with requested rates.
 * An estimate at the current census, not a forecast of future city growth.
 * Does not change live funds, map, RNG, options or histories. */
MPResult mp_quote_budget(MPGame *, int32_t tax, float police, float fire, float road, MPBudgetQuote *);
typedef struct MPFinance {
    int64_t city_time, funds, tax_income, operating_expenses, capital_expenses;
} MPFinance;
/* Up to 120 annual records, newest first; runtime only, like MicropolisJ.
 * Capacity query returns required size without modifying any records. */
MPResult mp_copy_finances(MPGame *, MPFinance *, size_t capacity, size_t *out_count);
typedef struct MPSound { int32_t kind, x, y; } MPSound;
/* kinds: 1 build, 2 reject, 3 explosion-high, 4 explosion-low,
 * 5 heavy traffic, 6 ship horn, 7 siren, 8 monster. Latest 32 retained. */
MPResult mp_poll_sounds(MPGame *, MPSound *, size_t capacity, size_t *out_count);
MPResult mp_set_sound_events(MPGame *, int32_t enabled);
typedef struct MPSprite {
    int32_t type, frame, x, y, width, height, x_offset, y_offset;
} MPSprite;
MPResult mp_copy_sprites(MPGame *, MPSprite *, size_t capacity, size_t *out_count);
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
/* Classic 27120-byte save for MicropolisJ File loader compatibility.
 * Rejects nonzero auxiliary tiles instead of discarding their data. */
MPResult mp_save_city_classic(MPGame *game, const char *utf8_path);
#ifdef __cplusplus
}
#endif
#endif
