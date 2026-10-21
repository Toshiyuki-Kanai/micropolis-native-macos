// SPDX-License-Identifier: GPL-3.0-or-later
// Verify the native animation boundary against the existing core, not a new table.
#include "micropolis.h"
#include "micropolis_native.h"
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#define CHECK(x) do { if (!(x)) { std::fprintf(stderr,"FAIL animation line %d: %s\n",__LINE__,#x); std::exit(1); } } while (0)
int main(int argc,char **argv) {
    CHECK(argc==3);
    CHECK(mp_animate_tiles(nullptr)==MP_INVALID_ARGUMENT);
    auto oracle=std::make_unique<Micropolis>(); oracle->init(); oracle->clearMap();
    oracle->setFunds(20000); oracle->setSpeed(3);
    // Every ID, both animated and static, with all other flags preserved.
    for (int id=0;id<1024;++id) {
        oracle->map[id%120][id/120]=id | ANIMBIT | BURNBIT | BULLBIT | CONDBIT;
        oracle->map[id%120][20+id/120]=id | BULLBIT;
    }
    const auto path=std::string(argv[2])+"/animation-fixture.cty";
    CHECK(oracle->saveFile(path));
    MPGame *game=nullptr; CHECK(mp_create(&game)==MP_OK);
    CHECK(mp_load_city(game,path.c_str())==MP_OK);
    CHECK(mp_set_speed(game,3)==MP_OK);
    uint16_t before[MP_TILE_COUNT], after[MP_TILE_COUNT];
    CHECK(mp_copy_map(game,0,before,MP_TILE_COUNT)==MP_OK);
    MPSnapshot initial,final; CHECK(mp_get_snapshot(game,&initial)==MP_OK);
    int changed=0;
    for (int frame=0;frame<32;++frame) {
        CHECK(mp_animate_tiles(game)==MP_OK);
        CHECK(mp_copy_map(game,0,after,MP_TILE_COUNT)==MP_OK);
        for (int i=0;i<MP_TILE_COUNT;++i) {
            auto expected=(before[i] & ANIMBIT)
                ? (before[i] & ALLBITS) | oracle->getNextAnimatedTile(before[i] & LOMASK)
                : before[i];
            CHECK(after[i]==expected);
            changed += after[i]!=before[i]; before[i]=after[i];
        }
    }
    CHECK(changed>0);
    CHECK(mp_get_snapshot(game,&final)==MP_OK);
    CHECK(final.city_time==initial.city_time && final.funds==initial.funds);
    for (int stopped=0;stopped<2;++stopped) {
        if (stopped==0) CHECK(mp_set_paused(game,1)==MP_OK);
        else { CHECK(mp_set_paused(game,0)==MP_OK); CHECK(mp_set_speed(game,0)==MP_OK); }
        CHECK(mp_animate_tiles(game)==MP_OK);
        CHECK(mp_copy_map(game,0,after,MP_TILE_COUNT)==MP_OK);
        for (int i=0;i<MP_TILE_COUNT;++i) CHECK(after[i]==before[i]);
    }
    mp_destroy(game);
    std::puts("PASS animation: all 1024 IDs, core table, status flags, 32 frames, pause/speed zero, no funds/time change");
}
