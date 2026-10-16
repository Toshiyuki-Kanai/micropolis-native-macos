/* SPDX-License-Identifier: GPL-3.0-or-later. Pure C consumer of the public ABI. */
#include "micropolis_native.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"FAIL C API line %d: %s\n",__LINE__,#x); exit(1); } } while(0)
static MPSnapshot snapshot(MPGame *g) { MPSnapshot s; CHECK(mp_get_snapshot(g,&s)==MP_OK); return s; }
static void *reader(void *ptr) {
    for(int i=0;i<200;++i) { MPSnapshot s; CHECK(mp_get_snapshot(ptr,&s)==MP_OK); }
    return NULL;
}
int main(int argc, char **argv) {
    CHECK(argc==3);
    MPGame *g=NULL, *other=NULL;
    CHECK(mp_create(NULL)==MP_INVALID_ARGUMENT);
    CHECK(mp_create(&g)==MP_OK && g); CHECK(mp_create(&other)==MP_OK);
    CHECK(mp_step(NULL,1)==MP_INVALID_ARGUMENT);
    CHECK(mp_step(g,1000001)==MP_INVALID_ARGUMENT);
    CHECK(mp_set_speed(g,-1)==MP_INVALID_ARGUMENT && mp_set_speed(g,4)==MP_INVALID_ARGUMENT);
    CHECK(mp_set_paused(g,2)==MP_INVALID_ARGUMENT);
    CHECK(mp_set_funding(g,-0.5f,1,1)==MP_INVALID_ARGUMENT);
    CHECK(mp_copy_map(g,0,NULL,MP_TILE_COUNT)==MP_INVALID_ARGUMENT);
    uint16_t map[MP_TILE_COUNT], mop[MP_TILE_COUNT];
    memset(map,0x5a,sizeof(map));
    CHECK(mp_copy_map(g,0,map,MP_TILE_COUNT-1)==MP_BUFFER_TOO_SMALL && map[0]==0x5a5a);
    CHECK(mp_build(g,999,10,10)==MP_INVALID_ARGUMENT);
    CHECK(mp_build(g,MP_TOOL_ROAD,-1,10)==MP_INVALID_ARGUMENT);
    MPSnapshot before=snapshot(g);
    CHECK(mp_build(g,MP_TOOL_ROAD,10,10)==MP_OK);
    CHECK(snapshot(g).funds==before.funds-10);
    CHECK(mp_copy_map(g,0,map,MP_TILE_COUNT)==MP_OK && (map[10*120+10]&0x3ff)!=0);
    CHECK(mp_build(g,MP_TOOL_RESIDENTIAL,20,20)==MP_OK);
    CHECK(mp_build(g,MP_TOOL_COMMERCIAL,30,20)==MP_OK);
    CHECK(mp_build(g,MP_TOOL_INDUSTRIAL,40,20)==MP_OK);
    // Place a 4x4 power plant on an existing zone: rejection must be atomic.
    before=snapshot(g); CHECK(mp_copy_map(g,0,map,MP_TILE_COUNT)==MP_OK);
    CHECK(mp_build(g,MP_TOOL_COAL_POWER,20,20)!=MP_OK);
    CHECK(mp_copy_map(g,0,mop,MP_TILE_COUNT)==MP_OK);
    CHECK(memcmp(map,mop,sizeof(map))==0 && snapshot(g).funds==before.funds);
    CHECK(mp_step(g,2000)==MP_OK && snapshot(g).city_time>before.city_time);
    CHECK(mp_set_paused(g,1)==MP_OK); before=snapshot(g);
    CHECK(mp_step(g,2000)==MP_OK && snapshot(g).city_time==before.city_time);
    CHECK(mp_set_speed(g,2)==MP_OK && snapshot(g).speed==2);
    CHECK(mp_set_paused(g,0)==MP_OK && snapshot(g).speed==2);
    CHECK(mp_step(g,2000)==MP_OK && snapshot(g).city_time>before.city_time);
    CHECK(snapshot(other).city_time==50); // no shared simulation state
    CHECK(mp_generate(g,12345)==MP_OK && snapshot(g).city_time==0);
    CHECK(mp_copy_map(g,0,map,MP_TILE_COUNT)==MP_OK);
    CHECK(mp_generate(other,12345)==MP_OK);
    CHECK(mp_copy_map(other,0,mop,MP_TILE_COUNT)==MP_OK);
    CHECK(memcmp(map,mop,sizeof(map))==0);
    char city[4096], save[4096], missing[4096];
    CHECK(snprintf(city,sizeof(city),"%s/content/micropolis/cities/haight.cty",argv[1])>0);
    CHECK(snprintf(save,sizeof(save),"%s/api-都市.cty",argv[2])>0);
    CHECK(snprintf(missing,sizeof(missing),"%s/absent/city.cty",argv[2])>0);
    CHECK(mp_load_city(g,city)==MP_OK && snapshot(g).funds==1000000);
    before=snapshot(g); CHECK(mp_step(g,2000)==MP_OK);
    CHECK(snapshot(g).city_time>before.city_time);
    pthread_t thread; CHECK(pthread_create(&thread,NULL,reader,g)==0);
    CHECK(mp_step(g,1100)==MP_OK); CHECK(pthread_join(thread,NULL)==0);
    CHECK(mp_set_funding(g,0.25f,0.5f,0.75f)==MP_OK);
    before=snapshot(g); CHECK(mp_copy_map(g,0,map,MP_TILE_COUNT)==MP_OK);
    CHECK(mp_save_city(g,save)==MP_OK);
    CHECK(mp_load_city(other,save)==MP_OK);
    MPSnapshot after=snapshot(other);
    CHECK(after.funds==before.funds && after.city_time==before.city_time);
    CHECK(after.police_fraction==0.25f && after.fire_fraction==0.5f && after.road_fraction==0.75f);
    CHECK(mp_copy_map(other,0,mop,MP_TILE_COUNT)==MP_OK);
    /* The legacy loader scans the city and refreshes road traffic/zone tiles.
     * Verify serialization against independent bytes; core_test separately
     * compares the full loaded map to the legacy C++ loader, including flags. */
    FILE *serialized=fopen(save,"rb"); CHECK(serialized);
    CHECK(fseek(serialized,3120,SEEK_SET)==0);
    for(int x=0;x<120;++x) for(int y=0;y<100;++y) {
        int hi=fgetc(serialized),lo=fgetc(serialized); CHECK(hi>=0 && lo>=0);
        CHECK(map[y*120+x]==(uint16_t)((hi<<8)|lo));
    }
    CHECK(mp_copy_map(g,1,map,MP_TILE_COUNT)==MP_OK);
    for(int x=0;x<120;++x) for(int y=0;y<100;++y) {
        int hi=fgetc(serialized),lo=fgetc(serialized); CHECK(hi>=0 && lo>=0);
        CHECK(map[y*120+x]==(uint16_t)((hi<<8)|lo));
    }
    CHECK(fgetc(serialized)==EOF); CHECK(fclose(serialized)==0);
    before=snapshot(g);
    CHECK(mp_load_city(g,missing)==MP_IO_ERROR);
    CHECK(snapshot(g).funds==before.funds && snapshot(g).revision==before.revision);
    CHECK(mp_save_city(g,missing)==MP_IO_ERROR);
    CHECK(mp_save_city(g,argv[2])==MP_IO_ERROR); /* rename onto a directory fails */
    FILE *bad=fopen(save,"wb"); CHECK(bad); CHECK(fputs("bad",bad)>=0); CHECK(fclose(bad)==0);
    CHECK(mp_load_city(g,save)==MP_IO_ERROR);
    CHECK(snapshot(g).funds==before.funds && snapshot(g).revision==before.revision);
    CHECK(mp_generate(other,7)==MP_OK);
    mp_destroy(other); CHECK(mp_create(&other)==MP_OK); /* empty map */
    CHECK(mp_save_city(other,save)==MP_OK);
    FILE *zero=fopen(save,"r+b"); CHECK(zero); CHECK(fseek(zero,2880+100,SEEK_SET)==0);
    CHECK(fwrite("\0\0\0\0",1,4,zero)==4); CHECK(fclose(zero)==0);
    CHECK(mp_load_city(other,save)==MP_OK && snapshot(other).funds==0);
    CHECK(mp_build(other,MP_TOOL_ROAD,10,10)==MP_NO_FUNDS && snapshot(other).funds==0);
    CHECK(mp_load_city(g,"")==MP_INVALID_ARGUMENT);
    CHECK(mp_load_city(g,NULL)==MP_INVALID_ARGUMENT);
    CHECK(strcmp(mp_result_string(MP_OK),"success")==0);
    mp_destroy(g); mp_destroy(other); mp_destroy(NULL);
    for(int i=0;i<20;++i) { CHECK(mp_create(&g)==MP_OK); CHECK(mp_generate(g,i)==MP_OK); mp_destroy(g); }
    puts("PASS pure C API: tools, funds, ticks, pause, generation, haight, save/load, errors, threads, lifecycle");
    return 0;
}
