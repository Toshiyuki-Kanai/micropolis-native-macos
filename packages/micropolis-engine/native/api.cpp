// SPDX-License-Identifier: GPL-3.0-or-later
// See MicropolisGPLLicenseNotice.md for Electronic Arts additional terms.
#include "micropolis_native.h"
#include "micropolis.h"
#include <memory>
#include <mutex>
#include <cmath>
#include <vector>
#include <deque>

class NativeCallback final : public ConsoleCallback {
public:
    std::deque<MPEvent> events;
    int earthquakeSequence=0;
    void startEarthquake(Micropolis *engine, emscripten::val, int) override {
        ++earthquakeSequence;
        if(!engine->enableSound) return;
        if(sounds.size()==32) sounds.pop_front();sounds.push_back({4,0,0});
    }
    std::deque<MPSound> sounds;
    void makeSound(Micropolis *, emscripten::val, std::string, std::string sound, int x, int y) override {
        int id=0;
        if(sound=="ExplosionHigh" || sound=="Explosion-High") id=3;
        else if(sound=="ExplosionLow" || sound=="Explosion-Low") id=4;
        else if(sound=="HeavyTraffic") id=5;
        else if(sound=="HonkHonkLow" || sound=="FogHornLow") id=6;
        else if(sound=="Siren") id=7;
        else if(sound=="Monster") id=8;
        else if(sound=="UhUh" || sound=="Sorry") id=2;
        if(id) { if(sounds.size()==32) sounds.pop_front();sounds.push_back({id,x,y}); }
    }
    MPInspection inspection{};
    void sendMessage(Micropolis *, emscripten::val, int id, int x, int y, bool, bool important) override {
        if (events.size() == 128) events.pop_front();
        events.push_back({id,x,y,important ? 1 : 0});
    }
    void showZoneStatus(Micropolis *, emscripten::val, int c, int d, int l, int r, int p, int g, int x, int y) override {
        inspection={c,d,l,r,p,g,x,y};
    }
};
struct MPGame {
    std::mutex mutex;
    std::unique_ptr<Micropolis> engine;
    uint64_t revision = 0;
    bool budgetPending = false;
    int64_t acceptedBudgetTime = -1;
    std::deque<MPFinance> finances;
    int64_t lastFinanceTime = -1;
    int64_t previousBalance = 20000;
};

static std::unique_ptr<Micropolis> makeEngine()
{
    auto engine = std::make_unique<Micropolis>();
    engine->setCallback(new NativeCallback(), emscripten::val::null());
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
        case MP_BUDGET_PENDING: return "approve the annual budget before saving";
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
        g.budgetPending=false; g.acceptedBudgetTime=-1;
        g.finances.clear();g.lastFinanceTime=-1;g.previousBalance=g.engine->totalFunds;
        ++g.revision;
        return MP_OK;
    });
}
MPResult mp_step(MPGame *game, uint32_t ticks)
{
    if (ticks > 1000000) return MP_INVALID_ARGUMENT;
    return access(game, [=](MPGame &g) -> MPResult {
        for (uint32_t i = 0; i < ticks; ++i) {
            auto &e=*g.engine;
            if (g.budgetPending) break;
            // Core phase 9 settles taxes. Pause before entry, never after spending.
            if (!e.simPaused && e.simSpeed && !e.autoBudget && e.phaseCycle==9 &&
                e.cityTime>0 && e.cityTime%48==0 && g.acceptedBudgetTime!=e.cityTime) {
                g.budgetPending=true; e.pause(); break;
            }
            const bool annual=!e.simPaused && e.simSpeed && e.phaseCycle==9 && e.cityTime>0 && e.cityTime%48==0;
            const int64_t fundsBefore=e.totalFunds;
            e.simTick();
            if(annual && e.phaseCycle!=9 && g.lastFinanceTime!=e.cityTime) {
                const int64_t income=e.totalPop>0 ? e.taxFund : 0;
                const int64_t expenses=fundsBefore+income-e.totalFunds;
                // Core auto-budget debits approved fractions, but its legacy
                // *Spend counters incorrectly store full requests. Use the core's
                // own approved values for service effects, as manual budgets do.
                if(e.totalPop>0) {
                    e.roadSpend=e.roadValue;e.fireSpend=e.fireValue;e.policeSpend=e.policeValue;
                    e.updateFundEffects();
                }
                g.finances.push_front({e.cityTime,e.totalFunds,income,expenses,
                    g.previousBalance-fundsBefore});
                if(g.finances.size()>120) g.finances.pop_back();
                g.lastFinanceTime=e.cityTime;g.previousBalance=e.totalFunds;
            }
        }
        if (ticks) ++g.revision;
        return MP_OK;
    });
}
MPResult mp_set_paused(MPGame *game, int32_t paused)
{
    if (paused != 0 && paused != 1) return MP_INVALID_ARGUMENT;
    return access(game, [=](MPGame &g) -> MPResult {
        if (!paused && g.budgetPending) return MP_INVALID_ARGUMENT;
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
        fresh->setGameLevel(GameLevel(std::max(0,std::min(2,int(fresh->miscHist[15])))));
        g.engine.swap(fresh);
        g.budgetPending=false; g.acceptedBudgetTime=-1;
        g.finances.clear();g.lastFinanceTime=-1;g.previousBalance=g.engine->totalFunds;
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
        ++g.revision; return MP_OK;
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
static MPResult saveCity(MPGame *game, const char *path,bool classic)
{
    if (!path || !*path) return MP_INVALID_ARGUMENT;
    return access(game, [=](MPGame &g) -> MPResult {
        if (g.budgetPending) return MP_BUDGET_PENDING;
        if (classic) for(int x=0;x<WORLD_W;++x) for(int y=0;y<WORLD_H;++y)
            if(g.engine->mop[x][y]) return MP_INVALID_ARGUMENT;
        std::string pattern = std::string(path) + ".tmp.XXXXXX";
        std::vector<char> name(pattern.begin(), pattern.end()); name.push_back('\0');
        int fd = mkstemp(name.data());
        if (fd < 0) return MP_IO_ERROR;
        close(fd);
        // No allocations occur in saveFile after the temp file is opened.
        g.engine->miscHist[15]=g.engine->gameLevel;
        g.engine->miscHist[16]=g.engine->cityClass;
        g.engine->miscHist[17]=g.engine->cityScore;
        bool ok = g.engine->saveFile(name.data());
        if (ok && classic) ok=truncate(name.data(),27120)==0;
        if (ok) ok = std::rename(name.data(), path) == 0;
        if (!ok) { unlink(name.data()); return MP_IO_ERROR; }
        return MP_OK;
    });
}
MPResult mp_save_city(MPGame *game,const char *path) { return saveCity(game,path,false); }
MPResult mp_save_city_classic(MPGame *game,const char *path) { return saveCity(game,path,true); }

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
MPResult mp_copy_overlay(MPGame *game, int32_t kind, int16_t *out, size_t capacity)
{
    if (!out || kind<0 || kind>8) return MP_INVALID_ARGUMENT;
    if (capacity<MP_TILE_COUNT) return MP_BUFFER_TOO_SMALL;
    return access(game,[=](MPGame &g)->MPResult {
        auto &e=*g.engine;
        for(int y=0;y<WORLD_H;++y) for(int x=0;x<WORLD_W;++x) {
            int v=0;
            switch(kind) {
                case 0:v=e.populationDensityMap.worldGet(x,y);break;
                case 1:v=e.rateOfGrowthMap.worldGet(x,y);break;
                case 2:v=e.landValueMap.worldGet(x,y);break;
                case 3:v=e.crimeRateMap.worldGet(x,y);break;
                case 4:v=e.pollutionDensityMap.worldGet(x,y);break;
                case 5:v=e.trafficDensityMap.worldGet(x,y);break;
                case 6:v=e.powerGridMap.worldGet(x,y);break;
                case 7:v=e.fireStationEffectMap.worldGet(x,y);break;
                case 8:v=e.policeStationEffectMap.worldGet(x,y);break;
            }
            out[y*WORLD_W+x]=int16_t(v);
        }
        return MP_OK;
    });
}
MPResult mp_copy_history(MPGame *game,int32_t type,int32_t scale,int16_t *out,size_t capacity)
{
    if (!out || type<0 || type>=HISTORY_TYPE_COUNT || scale<0 || scale>=HISTORY_SCALE_COUNT) return MP_INVALID_ARGUMENT;
    if (capacity<120) return MP_BUFFER_TOO_SMALL;
    return access(game,[=](MPGame &g)->MPResult {
        for(int i=0;i<120;++i) out[i]=g.engine->getHistory(type,scale,i);
        return MP_OK;
    });
}
MPResult mp_inspect(MPGame *game,int32_t x,int32_t y,MPInspection *out)
{
    if (!out || x<0 || x>=WORLD_W || y<0 || y>=WORLD_H) return MP_INVALID_ARGUMENT;
    return access(game,[=](MPGame &g)->MPResult {
        g.engine->doTool(TOOL_QUERY,short(x),short(y));
        *out=static_cast<NativeCallback *>(g.engine->callback)->inspection;
        // Core's legacy query table incorrectly maps dirt to category 29.
        if ((g.engine->map[x][y]&LOMASK)<RIVER) out->category=1;
        return MP_OK;
    });
}
MPResult mp_get_options(MPGame *game,MPOptions *out)
{
    if (!out) return MP_INVALID_ARGUMENT;
    return access(game,[=](MPGame &g)->MPResult {
        auto &e=*g.engine; *out={};
        out->difficulty=e.gameLevel;out->auto_bulldoze=e.autoBulldoze;
        out->auto_budget=e.autoBudget;out->budget_pending=g.budgetPending;
        out->population_delta=e.cityPopDelta;out->score_delta=e.cityScoreDelta;
        out->earthquake_sequence=static_cast<NativeCallback *>(e.callback)->earthquakeSequence;
        out->road_effect=int32_t(e.roadEffect);out->fire_effect=int32_t(e.fireEffect);out->police_effect=int32_t(e.policeEffect);
        for(int i=0;i<4;++i) {
            int id=e.problemOrder[i];out->problem_ids[i]=id;
            out->problem_votes[i]=(id>=0 && id<PROBNUM) ? e.problemVotes[id] : 0;
        }
        return MP_OK;
    });
}
MPResult mp_set_options(MPGame *game,int32_t level,int32_t bulldoze,int32_t budget)
{
    if (level<0 || level>2 || (bulldoze!=0 && bulldoze!=1) || (budget!=0 && budget!=1)) return MP_INVALID_ARGUMENT;
    return access(game,[=](MPGame &g)->MPResult {
        auto &e=*g.engine;e.setGameLevel(GameLevel(level));e.setAutoBulldoze(bulldoze!=0);e.setAutoBudget(budget!=0);
        if (budget && g.budgetPending) { g.acceptedBudgetTime=e.cityTime;g.budgetPending=false; }
        ++g.revision;return MP_OK;
    });
}
MPResult mp_generate_level(MPGame *game,int32_t seed,int32_t level)
{
    if (level<0 || level>2) return MP_INVALID_ARGUMENT;
    return access(game,[=](MPGame &g)->MPResult {
        auto fresh=makeEngine();fresh->generateSomeCity(seed);fresh->setGameLevelFunds(GameLevel(level));
        g.engine.swap(fresh);g.budgetPending=false;g.acceptedBudgetTime=-1;
        g.finances.clear();g.lastFinanceTime=-1;g.previousBalance=g.engine->totalFunds;++g.revision;return MP_OK;
    });
}
MPResult mp_accept_budget(MPGame *game)
{
    return access(game,[](MPGame &g)->MPResult {
        if (!g.budgetPending) return MP_INVALID_ARGUMENT;
        g.acceptedBudgetTime=g.engine->cityTime;g.budgetPending=false;++g.revision;return MP_OK;
    });
}
MPResult mp_poll_events(MPGame *game,MPEvent *out,size_t capacity,size_t *count)
{
    if (!count || (capacity && !out)) return MP_INVALID_ARGUMENT;
    return access(game,[=](MPGame &g)->MPResult {
        auto &events=static_cast<NativeCallback *>(g.engine->callback)->events;
        *count=std::min(capacity,events.size());
        for(size_t i=0;i<*count;++i) { out[i]=events.front();events.pop_front(); }
        return MP_OK;
    });
}
MPResult mp_copy_sprites(MPGame *game,MPSprite *out,size_t capacity,size_t *count)
{
    if (!count || (capacity && !out)) return MP_INVALID_ARGUMENT;
    return access(game,[=](MPGame &g)->MPResult {
        size_t n=0;for(auto *s=g.engine->spriteList;s;s=s->next) if(s->frame && s->type>=1 && s->type<=7) ++n;
        *count=n;if(capacity<n) return MP_BUFFER_TOO_SMALL;
        n=0;for(auto *s=g.engine->spriteList;s;s=s->next) if(s->frame && s->type>=1 && s->type<=7)
            out[n++]={s->type,s->frame,s->x,s->y,s->width,s->height,s->xOffset,s->yOffset};
        return MP_OK;
    });
}

MPResult mp_poll_sounds(MPGame *game,MPSound *out,size_t capacity,size_t *count)
{
    if (!count || (capacity && !out)) return MP_INVALID_ARGUMENT;
    return access(game,[=](MPGame &g)->MPResult {
        auto &sounds=static_cast<NativeCallback *>(g.engine->callback)->sounds;
        *count=std::min(capacity,sounds.size());
        for(size_t i=0;i<*count;++i) { out[i]=sounds.front();sounds.pop_front(); }
        return MP_OK;
    });
}

MPResult mp_copy_finances(MPGame *game,MPFinance *out,size_t capacity,size_t *count)
{
    if(!count || (capacity && !out)) return MP_INVALID_ARGUMENT;
    return access(game,[=](MPGame &g)->MPResult {
        *count=g.finances.size();if(capacity<*count) return MP_BUFFER_TOO_SMALL;
        size_t i=0;for(const auto &f:g.finances) out[i++]=f;return MP_OK;
    });
}

MPResult mp_edit_stroke(MPGame *game,MPTool tool,const MPPoint *points,size_t count,
                        int32_t commit,uint16_t *preview,size_t capacity,MPEdit *out)
{
    if (!out || !points || !count || count>MP_TILE_COUNT || tool<1 || tool>15 ||
        (commit!=0 && commit!=1)) return MP_INVALID_ARGUMENT;
    if (preview && capacity<MP_TILE_COUNT) return MP_BUFFER_TOO_SMALL;
    for(size_t i=0;i<count;++i) if(points[i].x<0 || points[i].x>=WORLD_W || points[i].y<0 || points[i].y>=WORLD_H)
        return MP_INVALID_ARGUMENT;
    return access(game,[=](MPGame &g)->MPResult {
        MPGame scratch;scratch.engine=makeEngine();auto &e=*g.engine;auto &s=*scratch.engine;
        for(int x=0;x<WORLD_W;++x) for(int y=0;y<WORLD_H;++y) { s.map[x][y]=e.map[x][y];s.mop[x][y]=e.mop[x][y]; }
        // Estimate the entire stroke even when the live city cannot afford it.
        // The core still decides each tool's true cost and valid sites.
        const int64_t scratchFunds=std::max<int64_t>(e.totalFunds,INT32_MAX);
        s.totalFunds=scratchFunds;s.autoBulldoze=e.autoBulldoze;s.doAnimation=e.doAnimation;s.enableSound=e.enableSound;s.nextRandom=e.nextRandom;
        *out={};out->status=MP_OK;
        for(size_t i=0;i<count;++i) {
            const auto result=mp_build(&scratch,tool,points[i].x,points[i].y);
            if(result==MP_OK) ++out->placed;
            else if(result==MP_NO_FUNDS) { out->status=result;break; }
            else if(result==MP_CANNOT_BUILD || result==MP_NEEDS_BULLDOZE) { ++out->rejected;if(!out->placed) out->status=result; }
            else return result;
        }
        out->cost=scratchFunds-s.totalFunds;
        if(out->cost>e.totalFunds) out->status=MP_NO_FUNDS;
        if(preview) for(int y=0;y<WORLD_H;++y) for(int x=0;x<WORLD_W;++x) preview[y*WORLD_W+x]=s.map[x][y];
        if(commit && out->status!=MP_NO_FUNDS && out->placed) {
            // Only tools run in the scratch engine. Preserve simulation, histories,
            // sprites and all runtime state of the live engine.
            for(int x=0;x<WORLD_W;++x) for(int y=0;y<WORLD_H;++y) { e.map[x][y]=s.map[x][y];e.mop[x][y]=s.mop[x][y]; }
            e.nextRandom=s.nextRandom;e.spend(int(out->cost));e.newMap=1;
            auto &source=*static_cast<NativeCallback *>(s.callback);
            auto &target=*static_cast<NativeCallback *>(e.callback);
            for(auto event:source.events) { if(target.events.size()==128) target.events.pop_front();target.events.push_back(event); }
            for(auto sound:source.sounds) { if(target.sounds.size()==32) target.sounds.pop_front();target.sounds.push_back(sound); }
            ++g.revision;
        }
        if(out->placed && out->status!=MP_NO_FUNDS) out->status=MP_OK;
        return MP_OK;
    });
}

MPResult mp_quote_budget(MPGame *game,int32_t tax,float police,float fire,float road,MPBudgetQuote *out)
{
    auto valid=[](float f){return std::isfinite(f) && f>=0 && f<=1;};
    if(!out || tax<0 || tax>20 || !valid(police) || !valid(fire) || !valid(road)) return MP_INVALID_ARGUMENT;
    return access(game,[=](MPGame &g)->MPResult {
        auto scratch=makeEngine();auto &s=*scratch;const auto &e=*g.engine;
        s.totalFunds=e.totalFunds;s.totalPop=e.totalPop;s.landValueAverage=e.landValueAverage;
        s.roadTotal=e.roadTotal;s.railTotal=e.railTotal;s.fireStationPop=e.fireStationPop;s.policeStationPop=e.policeStationPop;
        s.gameLevel=e.gameLevel;s.cityTax=short(tax);s.policePercent=police;s.firePercent=fire;s.roadPercent=road;
        s.cityTime=48;s.phaseCycle=9;s.initSimLoad=0;s.doInitialEval=false;s.simSpeed=3;s.simPaused=false;s.autoBudget=true;
        s.simTick();
        *out={s.totalPop>0 ? s.taxFund : 0,s.roadFund,s.fireFund,s.policeFund,
              s.totalPop>0 ? s.roadValue : 0,s.totalPop>0 ? s.fireValue : 0,s.totalPop>0 ? s.policeValue : 0,s.totalFunds};
        return MP_OK;
    });
}

MPResult mp_set_sound_events(MPGame *game,int32_t enabled)
{
    if(enabled!=0 && enabled!=1) return MP_INVALID_ARGUMENT;
    return access(game,[=](MPGame &g)->MPResult { g.engine->setEnableSound(enabled!=0);return MP_OK; });
}

}
