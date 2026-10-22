/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "micropolis_native.h"
#include <assert.h>
#include <stdio.h>
int main(int argc,char **argv) {
    assert(argc==3);MPGame *original=NULL,*java=NULL;
    assert(mp_create(&original)==MP_OK && mp_create(&java)==MP_OK);
    assert(mp_load_city(original,argv[1])==MP_OK && mp_load_city(java,argv[2])==MP_OK);
    MPSnapshot a,b;assert(mp_get_snapshot(original,&a)==MP_OK && mp_get_snapshot(java,&b)==MP_OK);
    assert(a.funds==b.funds && a.city_time==b.city_time);
    /* Compare serialized IDs: the core deliberately runs two initialization
     * scans on load, so loaded simulation maps can already evolve differently. */
    FILE *fa=fopen(argv[1],"rb"),*fb=fopen(argv[2],"rb");assert(fa && fb);
    assert(!fseek(fa,3120,SEEK_SET) && !fseek(fb,3120,SEEK_SET));
    for(int i=0;i<MP_TILE_COUNT;++i) {
        int ah=fgetc(fa),al=fgetc(fa),bh=fgetc(fb),bl=fgetc(fb);
        assert(ah>=0 && al>=0 && bh>=0 && bl>=0);
        assert((((ah<<8)|al)&1023)==(((bh<<8)|bl)&1023));
    }
    fclose(fa);fclose(fb);
    MPOptions oa,ob;assert(mp_get_options(original,&oa)==MP_OK && mp_get_options(java,&ob)==MP_OK);
    assert(oa.difficulty==ob.difficulty && oa.auto_bulldoze==ob.auto_bulldoze && oa.auto_budget==ob.auto_budget);
    assert(mp_step(java,2000)==MP_OK);assert(mp_get_snapshot(java,&b)==MP_OK && b.city_time>a.city_time);
    mp_destroy(java);mp_destroy(original);
    puts("PASS C API reopened official Java resave: tile IDs, funds/time, options, continuation");
}
