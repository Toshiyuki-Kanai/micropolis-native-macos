/* SPDX-License-Identifier: GPL-3.0-or-later
 * MicropolisJ feature boundary regression; no simulator reimplementation. */
#include "micropolis_native.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void ok(MPResult r) { if(r!=MP_OK) { fprintf(stderr,"C API: %s\n",mp_result_string(r));abort(); } }
int main(int argc,char **argv) {
    assert(argc==3);MPGame *g=NULL;ok(mp_create(&g));
    MPSnapshot s;MPOptions o;int16_t values[MP_TILE_COUNT];
    for(int level=0;level<3;++level) {
        ok(mp_generate_level(g,42,level));ok(mp_get_snapshot(g,&s));
        assert(s.funds==(level==0 ? 20000 : level==1 ? 10000 : 5000));
        ok(mp_get_options(g,&o));assert(o.difficulty==level);
    }
    int64_t funds=s.funds;
    ok(mp_set_options(g,0,0,0));ok(mp_get_snapshot(g,&s));assert(s.funds==funds);
    values[0]=-123;
    assert(mp_copy_overlay(g,0,values,11999)==MP_BUFFER_TOO_SMALL && values[0]==-123);
    assert(mp_copy_overlay(g,-1,values,MP_TILE_COUNT)==MP_INVALID_ARGUMENT);
    assert(mp_copy_history(g,6,0,values,120)==MP_INVALID_ARGUMENT);
    assert(mp_copy_history(g,0,2,values,120)==MP_INVALID_ARGUMENT);
    MPInspection q;assert(mp_inspect(g,120,0,&q)==MP_INVALID_ARGUMENT);
    assert(mp_set_options(g,3,0,0)==MP_INVALID_ARGUMENT);
    MPGame *editing=NULL;ok(mp_create(&editing));
    MPPoint points[4]={{10,10},{13,10},{10,13},{13,13}};MPEdit edit;
    uint16_t beforeMap[MP_TILE_COUNT],preview[MP_TILE_COUNT],afterMap[MP_TILE_COUNT];
    ok(mp_copy_map(editing,0,beforeMap,MP_TILE_COUNT));
    ok(mp_edit_stroke(editing,MP_TOOL_RESIDENTIAL,points,4,0,preview,MP_TILE_COUNT,&edit));
    assert(edit.placed==4 && edit.cost==400 && edit.status==MP_OK);
    ok(mp_copy_map(editing,0,afterMap,MP_TILE_COUNT));assert(!memcmp(beforeMap,afterMap,sizeof(beforeMap)));
    ok(mp_get_snapshot(editing,&s));assert(s.funds==20000);
    ok(mp_edit_stroke(editing,MP_TOOL_RESIDENTIAL,points,4,1,NULL,0,&edit));
    ok(mp_copy_map(editing,0,afterMap,MP_TILE_COUNT));assert(!memcmp(preview,afterMap,sizeof(preview)));
    ok(mp_get_snapshot(editing,&s));assert(s.funds==19600);
    MPPoint airports[2]={{40,40},{60,60}};
    memcpy(beforeMap,afterMap,sizeof(beforeMap));
    ok(mp_edit_stroke(editing,MP_TOOL_AIRPORT,airports,2,1,NULL,0,&edit));
    assert(edit.status==MP_NO_FUNDS && edit.cost==20000);ok(mp_get_snapshot(editing,&s));assert(s.funds==19600);
    ok(mp_copy_map(editing,0,afterMap,MP_TILE_COUNT));assert(!memcmp(beforeMap,afterMap,sizeof(beforeMap)));
    points[0].x=-1;assert(mp_edit_stroke(editing,MP_TOOL_ROAD,points,4,1,NULL,0,&edit)==MP_INVALID_ARGUMENT);
    ok(mp_set_sound_events(editing,1));MPPoint doze={10,10};
    ok(mp_edit_stroke(editing,MP_TOOL_BULLDOZER,&doze,1,1,NULL,0,&edit));
    MPSound dozeSounds[32];size_t dozeCount=0;ok(mp_poll_sounds(editing,dozeSounds,32,&dozeCount));
    assert(dozeCount>0 && dozeSounds[0].kind==3);
    mp_destroy(editing);
    puts("PASS engine-generated preview equals commit, preview unchanged, atomic rejection on insufficient total funds");
    char path[4096];snprintf(path,sizeof(path),"%s/gameplay-grown.cty",argv[2]);
    ok(mp_load_city(g,path));
    for(int kind=0;kind<9;++kind) {
        ok(mp_copy_overlay(g,kind,values,MP_TILE_COUNT));
        long sum=0;for(int i=0;i<MP_TILE_COUNT;++i) sum+=abs(values[i]);
        printf("PASS copied overlay %d (%ld absolute total)\n",kind,sum);
    }
    ok(mp_inspect(g,90,60,&q));assert(q.x==90 && q.y==60 && q.category==1);
    ok(mp_get_snapshot(g,&s));funds=s.funds;
    ok(mp_inspect(g,40,44,&q));ok(mp_get_snapshot(g,&s));assert(funds==s.funds);
    assert(q.density>=1 && q.density<=4 && q.land>=5 && q.land<=8);
    for(int scale=0;scale<2;++scale) for(int kind=0;kind<6;++kind) ok(mp_copy_history(g,kind,scale,values,120));
    ok(mp_set_options(g,2,0,0));ok(mp_configure_budget(g,9,.6f,.7f,.8f));
    ok(mp_get_options(g,&o));assert(!o.auto_budget);
    ok(mp_set_paused(g,0));
    int n=0;
    do { ok(mp_step(g,8));ok(mp_get_options(g,&o));assert(++n<20000); } while(!o.budget_pending);
    ok(mp_get_snapshot(g,&s));assert(s.paused && s.city_time%48==0);
    snprintf(path,sizeof(path),"%s/budget-pending.cty",argv[2]);
    FILE *protected=fopen(path,"wb");assert(protected);fputs("protected",protected);fclose(protected);
    assert(mp_save_city(g,path)==MP_BUDGET_PENDING);
    protected=fopen(path,"rb");assert(protected);char marker[10]={0};assert(fread(marker,1,9,protected)==9);fclose(protected);assert(!strcmp(marker,"protected"));
    MPBudgetQuote quote;ok(mp_quote_budget(g,9,.6f,.7f,.8f,&quote));
    MPSnapshot quoted;ok(mp_get_snapshot(g,&quoted));assert(quoted.funds==s.funds && quoted.city_time==s.city_time);
    assert(quote.balance==s.funds+quote.income-quote.road_funded-quote.fire_funded-quote.police_funded);
    assert(mp_quote_budget(g,21,.6f,.7f,.8f,&quote)==MP_INVALID_ARGUMENT);
    MPSnapshot stopped=s;ok(mp_step(g,1000));ok(mp_get_snapshot(g,&s));
    assert(s.city_time==stopped.city_time && s.funds==stopped.funds);
    assert(mp_set_paused(g,0)==MP_INVALID_ARGUMENT);
    ok(mp_accept_budget(g));ok(mp_set_paused(g,0));ok(mp_step(g,8));ok(mp_get_options(g,&o));assert(!o.budget_pending);
    ok(mp_get_snapshot(g,&s));assert(s.funds==quote.balance);
    MPFinance settled[120];size_t settledCount=0;
    ok(mp_copy_finances(g,settled,120,&settledCount));assert(settledCount>0);
    assert(settled[0].funds==quote.balance && settled[0].tax_income==quote.income);
    assert(settled[0].operating_expenses==quote.road_funded+quote.fire_funded+quote.police_funded);
    puts("PASS manual budget quote matches actual settlement funds, income and operating expenses");
    do { ok(mp_step(g,8));ok(mp_get_options(g,&o));assert(++n<40000); } while(!o.budget_pending);
    ok(mp_get_snapshot(g,&s));assert(s.city_time>stopped.city_time);
    ok(mp_set_options(g,2,0,1));ok(mp_set_paused(g,0));ok(mp_step(g,32));
    snprintf(path,sizeof(path),"%s/parity-options.cty",argv[2]);ok(mp_save_city(g,path));
    MPGame *restored=NULL;ok(mp_create(&restored));ok(mp_load_city(restored,path));ok(mp_get_options(restored,&o));
    assert(o.difficulty==2 && !o.auto_bulldoze && o.auto_budget);
    /* History values are the exact signed big-endian shorts of classic saves. */
    FILE *file=fopen(path,"rb");assert(file);
    int order[6]={0,1,2,5,3,4};
    for(int kind=0;kind<6;++kind) for(int scale=0;scale<2;++scale) {
        ok(mp_copy_history(g,kind,scale,values,120));
        assert(!fseek(file,order[kind]*480+scale*240,SEEK_SET));
        for(int i=0;i<120;++i) { int hi=fgetc(file),lo=fgetc(file);assert(hi>=0 && lo>=0);assert(values[i]==(int16_t)((hi<<8)|lo)); }
    }
    fclose(file);
    MPFinance finance[120];size_t financeCount=0;
    ok(mp_copy_finances(g,finance,120,&financeCount));assert(financeCount>=2);
    assert(finance[0].city_time>finance[1].city_time);
    assert(finance[0].funds==finance[1].funds+finance[0].tax_income-finance[0].operating_expenses-finance[0].capital_expenses);
    snprintf(path,sizeof(path),"%s/parity-classic.cty",argv[2]);ok(mp_save_city_classic(g,path));
    file=fopen(path,"rb");assert(file && !fseek(file,0,SEEK_END) && ftell(file)==27120);fclose(file);
    ok(mp_load_city(restored,path));
    /* Zero funding must also mean zero road service effect in automatic mode. */
    ok(mp_configure_budget(g,9,0,0,0));
    ok(mp_copy_finances(g,finance,120,&financeCount));size_t priorCount=financeCount;
    n=0;do {ok(mp_step(g,8));ok(mp_copy_finances(g,finance,120,&financeCount));assert(++n<20000);} while(financeCount==priorCount);
    ok(mp_get_options(g,&o));assert(o.road_effect==0 && finance[0].operating_expenses==0);
    puts("PASS auto-budget zero funding produces zero road service effect and zero operating expense");
    MPEvent events[128];size_t count;ok(mp_poll_events(g,events,128,&count));assert(count<=128);
    ok(mp_poll_events(g,events,128,&count));assert(count==0);
    ok(mp_trigger_disaster(g,MP_DISASTER_TORNADO));
    assert(mp_copy_sprites(g,NULL,0,&count)==MP_BUFFER_TOO_SMALL && count>0);
    MPSprite *sprites=calloc(count,sizeof(*sprites));size_t copied;
    ok(mp_copy_sprites(g,sprites,count,&copied));assert(count==copied);
    int found=0;for(size_t i=0;i<count;++i) if(sprites[i].type==6) { found=1;assert(sprites[i].frame>0 && sprites[i].frame<=3); }
    assert(found);free(sprites);
    ok(mp_set_sound_events(g,1));ok(mp_trigger_disaster(g,MP_DISASTER_EARTHQUAKE));
    MPSound sounds[32];ok(mp_poll_sounds(g,sounds,32,&count));assert(count>0 && count<=32);
    ok(mp_set_sound_events(g,0));ok(mp_trigger_disaster(g,MP_DISASTER_EARTHQUAKE));
    ok(mp_poll_sounds(g,sounds,32,&count));assert(count==0);
    mp_destroy(restored);mp_destroy(g);
    puts("PASS query, 9 overlays, 12 histories, options persistence, manual budgets before settlement, bounded events/sprites/sounds");
}
