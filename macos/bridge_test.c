#include "PodBridge.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned char *read_file(const char *path, size_t *n) {
    FILE *f=fopen(path,"rb"); assert(f); fseek(f,0,SEEK_END); *n=ftell(f); rewind(f);
    unsigned char *p=malloc(*n); assert(fread(p,1,*n,f)==*n); fclose(f); return p;
}
int main(int argc,char **argv) {
    assert(argc==3); size_t n,fn; unsigned char *bytes=read_file(argv[1],&n), *font=read_file(argv[2],&fn);
    assert(pod_open((const unsigned char *)"bad",3)==NULL); assert(strlen(pod_error())>0);
    PodDocument *doc=pod_open(bytes,n); if(!doc) {fprintf(stderr,"%s\n",pod_error()); return 1;}
    assert(pod_page_count(doc)==2); PodPage page; assert(pod_page(doc,0,&page)); assert(page.width==612);
    assert(!pod_page(doc,999,&page)); PodRun run; assert(pod_run(doc,0,0,&run)); assert(run.length>0);
    PodBitmap bitmap={0}; assert(pod_render(doc,0,font,fn,612,&bitmap)); assert(bitmap.height==792);
    size_t dark=0; for(size_t i=0;i<bitmap.length;i+=4) if(bitmap.data[i]<128) dark++;
    assert(dark>100); pod_buffer_free(bitmap.data,bitmap.length);
    assert(!pod_render(doc,0,font,fn,0,&bitmap));
    assert(!pod_replace(doc,0,0,(const unsigned char *)"this string is deliberately much too wide for the selected title",strlen("this string is deliberately much too wide for the selected title")));
    assert(pod_replace(doc,0,0,(const unsigned char *)"Hello Pod",9));
    PodBuffer out={0}; assert(pod_save(doc,&out)); PodDocument *again=pod_open(out.data,out.length); assert(again);
    assert(pod_run(again,0,0,&run)); assert(run.length==9 && memcmp(run.text,"Hello Pod",9)==0);
    size_t count=999; assert(pod_annotation_count(again,0,&count)); assert(count==0);
    PodStyle style={.stroke={0.1,0.5,0.2},.fill={1,0.8,0.1},.opacity=0.4,.width=2,.font_size=12,.has_fill=1};
    PodPoint points[]={{60,120},{180,180},{90,170}};
    for(uint32_t kind=0;kind<18;kind++) {
        assert(pod_annotation_put(again,0,0,kind,points,kind==5 ? 3:2,(const unsigned char *)"Note",4,style));
    }
    assert(pod_annotation_count(again,0,&count) && count==18);
    PodAnnotation mark={0}; assert(pod_annotation(again,0,17,&mark)); assert(mark.kind==17 && mark.style.opacity==0.4);
    uint32_t id=mark.id;
    assert(pod_annotation_put(again,0,id,17,points,2,(const unsigned char *)"Updated",7,style));
    assert(pod_annotation(again,0,17,&mark)); assert(mark.id==id && mark.text_length==7);
    PodBuffer annotated={0}; assert(pod_save(again,&annotated));
    PodDocument *reloaded=pod_open(annotated.data,annotated.length); assert(reloaded);
    assert(pod_annotation_count(reloaded,0,&count) && count==18);
    assert(pod_annotation_remove(reloaded,0,id)); assert(pod_annotation_count(reloaded,0,&count) && count==17);
    assert(!pod_annotation(reloaded,0,100,&mark));
    pod_close(reloaded); pod_buffer_free(annotated.data,annotated.length);
    pod_close(again); pod_buffer_free(out.data,out.length); pod_close(doc); free(bytes); free(font);
    puts("C bridge: open, render, bounds, rejection, replace, save/reopen, all18 annotation kinds, update/delete and cache invalidation passed");
}
