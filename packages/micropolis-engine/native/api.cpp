// SPDX-License-Identifier: GPL-3.0-or-later
// See MicropolisGPLLicenseNotice.md for Electronic Arts additional terms.
#include "micropolis_native.h"
#include "micropolis.h"
#include <memory>
#include <mutex>
#include <cmath>
#include <vector>

struct MPGame {
    std::mutex mutex;
    std::unique_ptr<Micropolis> engine;
    uint64_t revision = 0;
};

static std::unique_ptr<Micropolis> makeEngine()
{
    auto engine = std::make_unique<Micropolis>();
    engine->init();
    return engine;
}

template<class F> static MPResult access(MPGame *game, F operation) noexcept
{
    if (!game) return MP_INVALID_ARGUMENT;
    try {
        std::lock_guard<std::mutex> lock(game->mutex);
        return operation(*game);
    } catch (const std::bad_alloc &) { return MP_OUT_OF_MEMORY; }
      catch (...) { return MP_INTERNAL_ERROR; }
}

extern "C" {
const char *mp_result_string(MPResult result)
{
    switch (result) {
        case MP_OK: return "success";
        case MP_INVALID_ARGUMENT: return "invalid argument";
        case MP_BUFFER_TOO_SMALL: return "buffer too small";
        case MP_OUT_OF_MEMORY: return "out of memory; recreate engine";
        case MP_IO_ERROR: return "city I/O failed or unsupported city file";
        case MP_CANNOT_BUILD: return "cannot build here";
        case MP_NO_FUNDS: return "insufficient funds";
        case MP_NEEDS_BULLDOZE: return "clear the site first";
        case MP_INTERNAL_ERROR: return "internal error; recreate engine";
        default: return "unknown result";
    }
}
MPResult mp_create(MPGame **out_game)
{
    if (!out_game) return MP_INVALID_ARGUMENT;
    *out_game = nullptr;
    try {
        auto game = std::make_unique<MPGame>();
        game->engine = makeEngine();
        *out_game = game.release();
        return MP_OK;
    } catch (const std::bad_alloc &) { return MP_OUT_OF_MEMORY; }
      catch (...) { return MP_INTERNAL_ERROR; }
}
void mp_destroy(MPGame *game) { delete game; }
MPResult mp_generate(MPGame *game, int32_t seed)
{
    return access(game, [=](MPGame &g) -> MPResult {
        auto fresh = makeEngine();
        fresh->generateSomeCity(seed);
        g.engine.swap(fresh);
        ++g.revision;
        return MP_OK;
    });
}
MPResult mp_step(MPGame *game, uint32_t ticks)
{
    if (ticks > 1000000) return MP_INVALID_ARGUMENT;
    return access(game, [=](MPGame &g) -> MPResult {
        for (uint32_t i = 0; i < ticks; ++i) g.engine->simTick();
        if (ticks) ++g.revision;
        return MP_OK;
    });
}
MPResult mp_set_paused(MPGame *game, int32_t paused)
{
    if (paused != 0 && paused != 1) return MP_INVALID_ARGUMENT;
    return access(game, [=](MPGame &g) -> MPResult {
        if (paused) g.engine->pause(); else g.engine->resume();
        ++g.revision;
        return MP_OK;
    });
}
MPResult mp_set_speed(MPGame *game, int32_t speed)
{
    if (speed < 0 || speed > 3) return MP_INVALID_ARGUMENT;
    return access(game, [=](MPGame &g) -> MPResult {
        g.engine->setSpeed(short(speed));
        ++g.revision;
        return MP_OK;
    });
}
MPResult mp_set_funding(MPGame *game, float police, float fire, float road)
{
    auto valid=[](float f){ return std::isfinite(f) && f >= 0 && f <= 1; };
    if (!valid(police) || !valid(fire) || !valid(road)) return MP_INVALID_ARGUMENT;
    return access(game, [=](MPGame &g) -> MPResult {
        g.engine->policePercent = police;
        g.engine->firePercent = fire;
        g.engine->roadPercent = road;
        ++g.revision;
        return MP_OK;
    });
}
MPResult mp_get_snapshot(MPGame *game, MPSnapshot *out)
{
    if (!out) return MP_INVALID_ARGUMENT;
    return access(game, [=](MPGame &g) -> MPResult {
        auto &e = *g.engine;
        *out = {};
        out->city_time = e.cityTime; out->funds = e.totalFunds;
        out->population = e.cityPop; out->revision = g.revision;
        out->speed = e.simPaused ? e.simPausedSpeed : e.simSpeed;
        out->paused = e.simPaused;
        out->year = int32_t(e.cityTime / 48 + e.startingYear);
        out->month = int32_t((e.cityTime % 48) / 4);
        out->police_fraction = e.policePercent;
        out->fire_fraction = e.firePercent; out->road_fraction = e.roadPercent;
        return MP_OK;
    });
}
MPResult mp_copy_map(MPGame *game, int32_t mop, uint16_t *out, size_t capacity)
{
    if (!out || (mop != 0 && mop != 1)) return MP_INVALID_ARGUMENT;
    if (capacity < MP_TILE_COUNT) return MP_BUFFER_TOO_SMALL;
    return access(game, [=](MPGame &g) -> MPResult {
        for (int y=0; y<WORLD_H; ++y) for (int x=0; x<WORLD_W; ++x)
            out[y*WORLD_W+x] = mop ? g.engine->mop[x][y] : g.engine->map[x][y];
        return MP_OK;
    });
}
MPResult mp_build(MPGame *game, MPTool tool, int32_t x, int32_t y)
{
    if (x < 0 || x >= WORLD_W || y < 0 || y >= WORLD_H) return MP_INVALID_ARGUMENT;
    EditingTool selected;
    switch (tool) {
        case MP_TOOL_ROAD: selected=TOOL_ROAD; break;
        case MP_TOOL_RESIDENTIAL: selected=TOOL_RESIDENTIAL; break;
        case MP_TOOL_COMMERCIAL: selected=TOOL_COMMERCIAL; break;
        case MP_TOOL_INDUSTRIAL: selected=TOOL_INDUSTRIAL; break;
        case MP_TOOL_BULLDOZER: selected=TOOL_BULLDOZER; break;
        case MP_TOOL_WIRE: selected=TOOL_WIRE; break;
        case MP_TOOL_RAILROAD: selected=TOOL_RAILROAD; break;
        case MP_TOOL_PARK: selected=TOOL_PARK; break;
        case MP_TOOL_COAL_POWER: selected=TOOL_COALPOWER; break;
        case MP_TOOL_NUCLEAR_POWER: selected=TOOL_NUCLEARPOWER; break;
        case MP_TOOL_POLICE: selected=TOOL_POLICESTATION; break;
        case MP_TOOL_FIRE: selected=TOOL_FIRESTATION; break;
        case MP_TOOL_STADIUM: selected=TOOL_STADIUM; break;
        case MP_TOOL_SEAPORT: selected=TOOL_SEAPORT; break;
        case MP_TOOL_AIRPORT: selected=TOOL_AIRPORT; break;
        default: return MP_INVALID_ARGUMENT;
    }
    return access(game, [=](MPGame &g) -> MPResult {
        switch (g.engine->doTool(selected, short(x), short(y))) {
            case TOOLRESULT_OK: ++g.revision; return MP_OK;
            case TOOLRESULT_NO_MONEY: return MP_NO_FUNDS;
            case TOOLRESULT_NEED_BULLDOZE: return MP_NEEDS_BULLDOZE;
            default: return MP_CANNOT_BUILD;
        }
    });
}
MPResult mp_load_city(MPGame *game, const char *path)
{
    if (!path || !*path) return MP_INVALID_ARGUMENT;
    return access(game, [=](MPGame &g) -> MPResult {
        auto fresh = makeEngine();
        if (!fresh->loadCity(path)) return MP_IO_ERROR;
        g.engine.swap(fresh);
        ++g.revision;
        return MP_OK;
    });
}
// Gameplay additions, 2026-10-17. Delegate all simulation decisions to the core.
MPResult mp_get_details(MPGame *game, MPDetails *out)
{
    if (!out) return MP_INVALID_ARGUMENT;
    return access(game, [=](MPGame &g) -> MPResult {
        auto &e = *g.engine; *out = {};
        out->tax_income=e.taxFund; out->road_cost=e.roadFund;
        out->police_cost=e.policeFund; out->fire_cost=e.fireFund;
        out->assessed_value=e.cityAssessedValue; out->tax_rate=e.cityTax;
        out->score=e.cityScore; out->approval=e.cityYes; out->city_class=e.cityClass;
        out->powered_zones=e.poweredZoneCount; out->unpowered_zones=e.unpoweredZoneCount;
        out->coal_plants=e.coalPowerPop; out->nuclear_plants=e.nuclearPowerPop;
        out->residential_demand=e.resValve; out->commercial_demand=e.comValve;
        out->industrial_demand=e.indValve; out->pollution=e.pollutionAverage;
        out->crime=e.crimeAverage; out->traffic=e.trafficAverage;
        out->disasters=e.enableDisasters; out->auto_budget=e.autoBudget;
        return MP_OK;
    });
}
MPResult mp_configure_budget(MPGame *game, int32_t tax, float police, float fire, float road)
{
    auto valid=[](float f){ return std::isfinite(f) && f>=0 && f<=1; };
    if (tax<0 || tax>20 || !valid(police) || !valid(fire) || !valid(road)) return MP_INVALID_ARGUMENT;
    return access(game, [=](MPGame &g) -> MPResult {
        auto &e=*g.engine;
        e.setCityTax(short(tax)); e.policePercent=police; e.firePercent=fire; e.roadPercent=road;
        e.setAutoBudget(true); ++g.revision; return MP_OK;
    });
}
MPResult mp_set_disasters(MPGame *game, int32_t enabled)
{
    if (enabled!=0 && enabled!=1) return MP_INVALID_ARGUMENT;
    return access(game, [=](MPGame &g) -> MPResult {
        g.engine->setEnableDisasters(enabled!=0); ++g.revision; return MP_OK;
    });
}
MPResult mp_trigger_disaster(MPGame *game, int32_t disaster)
{
    if (disaster<MP_DISASTER_FIRE || disaster>MP_DISASTER_MELTDOWN) return MP_INVALID_ARGUMENT;
    return access(game, [=](MPGame &g) -> MPResult {
        switch(disaster) {
            case MP_DISASTER_FIRE: g.engine->makeFire(); break;
            case MP_DISASTER_FLOOD: g.engine->makeFlood(); break;
            case MP_DISASTER_TORNADO: g.engine->makeTornado(); break;
            case MP_DISASTER_EARTHQUAKE: g.engine->makeEarthquake(); break;
            case MP_DISASTER_MONSTER: g.engine->makeMonster(); break;
            case MP_DISASTER_MELTDOWN: g.engine->makeMeltdown(); break;
        }
        ++g.revision; return MP_OK;
    });
}
MPResult mp_save_city(MPGame *game, const char *path)
{
    if (!path || !*path) return MP_INVALID_ARGUMENT;
    return access(game, [=](MPGame &g) -> MPResult {
        std::string pattern = std::string(path) + ".tmp.XXXXXX";
        std::vector<char> name(pattern.begin(), pattern.end()); name.push_back('\0');
        int fd = mkstemp(name.data());
        if (fd < 0) return MP_IO_ERROR;
        close(fd);
        // No allocations occur in saveFile after the temp file is opened.
        bool ok = g.engine->saveFile(name.data());
        if (ok) ok = std::rename(name.data(), path) == 0;
        if (!ok) { unlink(name.data()); return MP_IO_ERROR; }
        return MP_OK;
    });
}
MPResult mp_animate_tiles(MPGame *game)
{
    return access(game, [](MPGame &g) -> MPResult {
        auto &e=*g.engine;
        if (!e.simPaused && e.simSpeed>0 && e.doAnimation) {
            e.animateTiles(); ++g.revision;
        }
        return MP_OK;
    });
}
}
