/* SPDX-License-Identifier: GPL-3.0-or-later. Gameplay acceptance, 2026-10-17. */
#include "micropolis_native.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
_Static_assert(sizeof(MPSnapshot)==64, "ABI v1 snapshot layout changed");
#define CHECK(x) do { if(!(x)) { fprintf(stderr,"FAIL gameplay line %d: %s\n",__LINE__,#x); exit(1); } } while(0)
static MPSnapshot state(MPGame*g){ MPSnapshot s; CHECK(mp_get_snapshot(g,&s)==MP_OK); return s; }
static MPDetails detail(MPGame*g){ MPDetails d; CHECK(mp_get_details(g,&d)==MP_OK); return d; }
static void build(MPGame*g,int tool,int x,int y){ CHECK(mp_build(g,tool,x,y)==MP_OK); }
int main(int argc,char**argv){
 CHECK(argc==3);
 MPGame*g=NULL;
 /* Each real engine tool on a funded empty city; none is a map-writing stub. */
 for(int tool=1;tool<=15;tool++){
  CHECK(mp_create(&g)==MP_OK);
  if(tool==MP_TOOL_BULLDOZER) build(g,MP_TOOL_ROAD,30,30);
  int64_t before=state(g).funds;
  build(g,tool,30,30);
  CHECK(state(g).funds<before);
  uint16_t tiles[MP_TILE_COUNT];CHECK(mp_copy_map(g,0,tiles,MP_TILE_COUNT)==MP_OK);
  if(tool!=MP_TOOL_BULLDOZER) CHECK((tiles[30*120+30]&0x3ff)!=0);
  mp_destroy(g);
 }
 puts("PASS all 15 native building tools and costs");
 CHECK(mp_create(&g)==MP_OK);
 CHECK(mp_get_details(g,NULL)==MP_INVALID_ARGUMENT);
 CHECK(mp_configure_budget(g,21,1,1,1)==MP_INVALID_ARGUMENT);
 CHECK(mp_configure_budget(g,7,NAN,1,1)==MP_INVALID_ARGUMENT);
 CHECK(mp_set_disasters(g,2)==MP_INVALID_ARGUMENT);
 CHECK(mp_trigger_disaster(g,7)==MP_INVALID_ARGUMENT);
 CHECK(mp_set_disasters(g,0)==MP_OK);
 CHECK(mp_configure_budget(g,0,1,1,1)==MP_OK);
 build(g,MP_TOOL_COAL_POWER,8,25);
 for(int x=10;x<65;x++)build(g,MP_TOOL_ROAD,x,29);
 for(int x=15;x<35;x+=4)build(g,MP_TOOL_RESIDENTIAL,x,27);
 for(int x=15;x<31;x+=4)build(g,MP_TOOL_COMMERCIAL,x,31);
 for(int x=39;x<55;x+=4)build(g,MP_TOOL_INDUSTRIAL,x,31);
 for(int x=11;x<60;x++)build(g,MP_TOOL_WIRE,x,25);
 for(int y=26;y<=33;y++)build(g,MP_TOOL_WIRE,12,y);
 for(int x=13;x<60;x++)build(g,MP_TOOL_WIRE,x,33);
 CHECK(mp_step(g,4000)==MP_OK);
 MPDetails d=detail(g);MPSnapshot grown=state(g);
 CHECK(grown.population>0 && d.powered_zones>0 && d.coal_plants==1);
 printf("PASS new city + roads + RCI + coal/wire + growth: population=%lld, powered=%d, time=%lld\n",(long long)grown.population,d.powered_zones,(long long)grown.city_time);
 CHECK(mp_configure_budget(g,9,0.25f,0.5f,0.75f)==MP_OK);
 CHECK(detail(g).tax_rate==9 && detail(g).auto_budget);
 CHECK(mp_set_paused(g,1)==MP_OK);
 char path[4096];snprintf(path,sizeof(path),"%s/gameplay-grown.cty",argv[2]);
 MPSnapshot saved=state(g);CHECK(mp_save_city(g,path)==MP_OK);mp_destroy(g);
 CHECK(mp_create(&g)==MP_OK); CHECK(mp_load_city(g,path)==MP_OK);
 CHECK(state(g).funds==saved.funds && state(g).city_time==saved.city_time);
 CHECK(detail(g).tax_rate==9 && state(g).police_fraction==0.25f && state(g).fire_fraction==0.5f && state(g).road_fraction==0.75f);
 CHECK(mp_set_disasters(g,0)==MP_OK);CHECK(mp_step(g,4000)==MP_OK);
 CHECK(state(g).city_time>saved.city_time && state(g).population>0);
 puts("PASS save, destroy, recreate, load, restore funds/time/tax/funding, continue city growth");
 for(int i=0;i<20;i++) CHECK(mp_step(g,16000)==MP_OK);
 printf("PASS long simulation: 328000 ticks, time=%lld funds=%lld\n",(long long)state(g).city_time,(long long)state(g).funds);
 char haight[4096];snprintf(haight,sizeof(haight),"%s/content/micropolis/cities/haight.cty",argv[1]);
 for(int i=0;i<20;i++){
  CHECK(mp_generate(g,i)==MP_OK);CHECK(mp_load_city(g,haight)==MP_OK);
  CHECK(mp_step(g,2000)==MP_OK);CHECK(state(g).city_time==4964);
 }
 puts("PASS 20 generation/haight load/2000 tick cycles");
 for(int disaster=1;disaster<=6;disaster++){
  CHECK(mp_load_city(g,haight)==MP_OK);
  CHECK(mp_trigger_disaster(g,disaster)==MP_OK);CHECK(mp_step(g,64)==MP_OK);
 }
 puts("PASS six engine disaster operations and subsequent simulation");
 mp_destroy(g);return 0;
}
