// SPDX-License-Identifier: GPL-3.0-or-later
// Regression tests for native and WASM-shared core fixes; see root GPL notices.
#include "micropolis.h"
#include "micropolis_native.h"
#include <array>
#include <fstream>
#include <iterator>
#include <memory>
#include <stdexcept>
#include <cstdio>
#include <new>
#include <cstdint>
#include <cmath>
#include <filesystem>

#define REQUIRE(expr) do { if (!(expr)) throw std::runtime_error(#expr); } while (0)
static std::vector<unsigned char> bytes(const std::string &path) {
    std::ifstream f(path, std::ios::binary);
    REQUIRE(f.good());
    return {std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>()};
}
static uint32_t u32(const std::vector<unsigned char> &b, size_t offset) {
    return (uint32_t(b[offset])<<24) | (uint32_t(b[offset+1])<<16) |
           (uint32_t(b[offset+2])<<8) | b[offset+3];
}
static void put32(std::vector<unsigned char> &b, size_t offset, uint32_t v) {
    for (int i=0;i<4;++i) b[offset+i] = static_cast<unsigned char>(v>>(24-i*8));
}
static void write(const std::string &path, const std::vector<unsigned char> &b) {
    std::ofstream f(path,std::ios::binary); f.write((const char*)b.data(), b.size()); REQUIRE(f.good());
}
int main(int argc, char **argv) {
    try {
        REQUIRE(argc == 3);
        const std::string repo=argv[1], out=argv[2];
        // Constructor must work over dirty storage, without relying on calloc.
        alignas(Micropolis) unsigned char storage[sizeof(Micropolis)];
        memset(storage,0xa5,sizeof(storage));
        auto dirty = new(storage) Micropolis;
        dirty->init(); dirty->~Micropolis();
        { Micropolis uninitialized; } // destruction before init is also valid
        auto m=std::make_unique<Micropolis>(); m->init();
        m->generateSomeCity(12345); m->clearMap(); m->setFunds(20000);
        REQUIRE(m->doTool(TOOL_ROAD,10,10)==TOOLRESULT_OK);
        REQUIRE(m->totalFunds == 19990);
        REQUIRE((m->map[10][10] & LOMASK) != DIRT);
        for (auto tool : {TOOL_RESIDENTIAL,TOOL_COMMERCIAL,TOOL_INDUSTRIAL})
            REQUIRE(m->doTool(tool,20+int(tool)*5,30)==TOOLRESULT_OK);
        m->setEnableDisasters(false); m->setSpeed(3);
        auto initial=m->cityTime;
        for (int i=0;i<2000;++i) m->simTick();
        REQUIRE(m->cityTime>initial);
        m->pause(); initial=m->cityTime;
        for(int i=0;i<100;++i) m->simTick();
        REQUIRE(m->cityTime==initial);
        m->setSpeed(2); m->resume(); REQUIRE(m->simSpeed==2);
        std::printf("PASS core generation, tools, funds, 2000 ticks, pause/resume\n");

        // Exercise pooled sprites and non-SSO std::string lifetime.
        auto sprite=m->newSprite(std::string(200,'s'),SPRITE_AIRPLANE,100,100);
        m->destroySprite(sprite);
        REQUIRE(m->newSprite("",SPRITE_AIRPLANE,100,100)==sprite);
        m->init();
        REQUIRE(m->spriteList==nullptr);
        REQUIRE(m->loadCity(repo+"/content/micropolis/cities/haight.cty"));
        REQUIRE(m->totalFunds==1000000 && m->cityTime==4839);
        m->newSprite("airport-test",SPRITE_AIRPLANE,100,100);
        m->setEnableDisasters(false); initial=m->cityTime;
        for (int i=0;i<2000;++i) m->simTick();
        REQUIRE(m->cityTime>initial);
        std::printf("PASS haight load, sprites and 2000 ticks: %ld -> %ld\n",long(initial),long(m->cityTime));

        // An independent byte fixture tests big-endian values and non-default
        // fractions, rather than allowing matching encoder/decoder bugs.
        const size_t hist=6*480;
        auto fixture=bytes(repo+"/content/micropolis/cities/haight.cty");
        REQUIRE(fixture.size()==27120);
        put32(fixture,hist+50*2,123456789);
        put32(fixture,hist+8*2,54321);
        put32(fixture,hist+58*2,16384); // 0.25
        put32(fixture,hist+60*2,32768); // 0.5
        put32(fixture,hist+62*2,49152); // 0.75
        write(out+"/fixture.cty",fixture);
        m->init(); REQUIRE(m->loadCity(out+"/fixture.cty"));
        REQUIRE(m->totalFunds==123456789 && m->cityTime==54321);
        REQUIRE(m->policePercent==0.25f && m->firePercent==0.5f && m->roadPercent==0.75f);
        REQUIRE(m->miscHist[10]==short((fixture[hist+20]<<8)|fixture[hist+21]));
        for (int x=0;x<WORLD_W;++x) for(int y=0;y<WORLD_H;++y) REQUIRE(m->mop[x][y]==0);
        m->map[3][7]=0x4321; m->mop[3][7]=0xabcd;
        m->miscHist[10]=1234; m->miscHist[11]=2345;
        m->miscHist[64]=3456; m->miscHist[65]=4567;
        REQUIRE(m->saveFile(out+"/roundtrip.cty"));
        auto saved=bytes(out+"/roundtrip.cty"); REQUIRE(saved.size()==51120);
        REQUIRE(u32(saved,hist+50*2)==123456789 && u32(saved,hist+8*2)==54321);
        REQUIRE(u32(saved,hist+58*2)==16384 && u32(saved,hist+60*2)==32768 && u32(saved,hist+62*2)==49152);
        REQUIRE(m->miscHist[10]==1234 && m->miscHist[11]==2345 && m->miscHist[64]==3456 && m->miscHist[65]==4567);
        const size_t index=3*100+7;
        REQUIRE(saved[3120+index*2]==0x43 && saved[3121+index*2]==0x21);
        REQUIRE(saved[27120+index*2]==0xab && saved[27121+index*2]==0xcd);
        REQUIRE(m->loadFileData(out+"/roundtrip.cty"));
        REQUIRE(m->map[3][7]==0x4321 && m->mop[3][7]==0xabcd);
        // Legacy load reseeds from the clock and scans active roads/zones.
        // Use a static map fixture for full raw-map equivalence, while the
        // live-city tests above verify actual simulation and byte preservation.
        auto staticFixture=saved;
        std::fill(staticFixture.begin()+3120,staticFixture.begin()+27120,0);
        staticFixture[3120+index*2]=0x10; // BULLBIT, no zone/road/animation
        staticFixture[3121+index*2]=0;
        write(out+"/static.cty",staticFixture);
        MPGame *api=nullptr; REQUIRE(mp_create(&api)==MP_OK);
        REQUIRE(mp_load_city(api,(out+"/static.cty").c_str())==MP_OK);
        auto reference=std::make_unique<Micropolis>(); reference->init();
        REQUIRE(reference->loadCity(out+"/static.cty"));
        std::array<uint16_t,MP_TILE_COUNT> apiMap;
        REQUIRE(mp_copy_map(api,0,apiMap.data(),apiMap.size())==MP_OK);
        for(int y=0;y<WORLD_H;++y) for(int x=0;x<WORLD_W;++x)
            REQUIRE(apiMap[y*WORLD_W+x]==reference->map[x][y]);
        REQUIRE(mp_copy_map(api,1,apiMap.data(),apiMap.size())==MP_OK);
        for(int y=0;y<WORLD_H;++y) for(int x=0;x<WORLD_W;++x)
            REQUIRE(apiMap[y*WORLD_W+x]==reference->mop[x][y]);
        mp_destroy(api);
        // Signed 32-bit funds and the zero/one funding endpoints.
        put32(fixture,hist+50*2,0xffffcfc7); // -12345
        put32(fixture,hist+58*2,0); put32(fixture,hist+60*2,65536);
        write(out+"/negative.cty",fixture);
        REQUIRE(m->loadCity(out+"/negative.cty")); REQUIRE(m->totalFunds==-12345);
        REQUIRE(m->policePercent==0 && m->firePercent==1);
        REQUIRE(m->saveFile(out+"/negative-roundtrip.cty"));
        REQUIRE(u32(bytes(out+"/negative-roundtrip.cty"),hist+50*2)==0xffffcfc7);
        // A failed write must never byte-swap the live maps or histories.
        auto tile=m->map[3][7];
        REQUIRE(!m->saveFile(out+"/missing-dir/file.cty")); REQUIRE(m->map[3][7]==tile);
#ifdef __linux__
        REQUIRE(!m->saveFile("/dev/full")); REQUIRE(m->map[3][7]==tile);
#endif
        write(out+"/invalid.cty",{1,2,3});
        REQUIRE(!m->loadFileData(out+"/invalid.cty")); REQUIRE(m->map[3][7]==tile);
        std::printf("PASS classic/extended formats, byte oracle, funding, histories, failed I/O\n");
        // All bundled classic cities are read-only inputs, including scenarios.
        for (const char *name : {"scenario_dullsville","scenario_san_francisco","scenario_hamburg","scenario_bern","scenario_tokyo","scenario_detroit","scenario_boston","scenario_rio_de_janeiro"}) {
            m->init(); REQUIRE(m->loadCity(repo+"/content/micropolis/cities/"+name+".cty"));
            m->setEnableDisasters(false);
            for(int i=0;i<1100;++i) m->simTick();
        }
        std::printf("PASS eight bundled scenario files, 1100 ticks each\n");
        // Exercise the legacy entrypoint itself, not only loadCity: constructing
        // its local std::strings from NULL used to fail before any file I/O.
        const auto previousDirectory = std::filesystem::current_path();
        std::filesystem::current_path(std::filesystem::path(repo) / "content/micropolis");
        for (int scenario = SC_DULLSVILLE; scenario <= SC_RIO; ++scenario) {
            m->init();
            m->loadScenario(static_cast<Scenario>(scenario));
            REQUIRE(m->scenario == scenario);
            REQUIRE(!m->cityName.empty());
        }
        std::filesystem::current_path(previousDirectory);
        m->setYear(2050); REQUIRE(m->currentYear() == 2050);
        m->setYear(-1); REQUIRE(m->currentYear() == m->startingYear);
        m->setCityName(std::string(100000, 'A'));
        REQUIRE(m->cityName.size() == 100000);
        m->setFunds(2147483647); m->spend(10);
        REQUIRE(m->totalFunds == 2147483637);
        m->setFunds(-2147483647); m->spend(1);
        REQUIRE(m->totalFunds == -2147483647 - 1);
        std::printf("PASS direct scenario entrypoint, year reset, long names and signed funds boundaries\n");
        return 0;
    } catch (const std::exception &e) { std::fprintf(stderr,"FAIL core: %s\n",e.what()); return 1; }
}
