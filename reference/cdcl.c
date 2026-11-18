#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct { int size; int lits[1]; } Cl;
typedef struct { Cl **a; int n, cap; } Vec;
static int nV; static signed char *val; static int *lvl, *trail, trailN, qhead, *lim, nLim; static Cl **reason;
static Vec *wat; static double *act, inc=1; static signed char *phase; static char *seen;
static int *heap, *hpos, hN; static int *learnt, learntN;
#define NEG(l) ((l)^1)
#define VAR(l) ((l)>>1)
static void vpush(Vec*v, Cl*c){ if(v->n==v->cap){v->cap=v->cap?2*v->cap:4; v->a=realloc(v->a,sizeof(Cl*)*v->cap);} v->a[v->n++]=c; }
static void hup(int i){ int v=heap[i]; while(i>0){int p=(i-1)/2; if(act[heap[p]]>=act[v])break; heap[i]=heap[p]; hpos[heap[i]]=i; i=p;} heap[i]=v; hpos[v]=i; }
static void hdown(int i){ int v=heap[i]; for(;;){int c=2*i+1; if(c>=hN)break; if(c+1<hN&&act[heap[c+1]]>act[heap[c]])c++; if(act[heap[c]]<=act[v])break; heap[i]=heap[c]; hpos[heap[i]]=i; i=c;} heap[i]=v; hpos[v]=i; }
static void hins(int v){ if(hpos[v]>=0)return; heap[hN]=v; hpos[v]=hN; hN++; hup(hN-1); }
static int hpop(){ int v=heap[0]; hN--; hpos[v]=-1; if(hN>0){heap[0]=heap[hN]; hpos[heap[0]]=0; hdown(0);} return v; }
static void enq(int l, Cl*r){ val[l]=1; val[NEG(l)]=-1; lvl[VAR(l)]=nLim; reason[VAR(l)]=r; trail[trailN++]=l; }
static Cl* propagate(){
  while(qhead<trailN){ int p=trail[qhead++]; int fl=NEG(p); Vec*w=&wat[fl]; int i=0,j=0;
    while(i<w->n){ Cl*c=w->a[i++]; if(c->lits[0]==fl){c->lits[0]=c->lits[1]; c->lits[1]=fl;}
      if(val[c->lits[0]]==1){w->a[j++]=c; continue;}
      int k; for(k=2;k<c->size;k++) if(val[c->lits[k]]!=-1) break;
      if(k<c->size){ c->lits[1]=c->lits[k]; c->lits[k]=fl; vpush(&wat[c->lits[1]],c); continue; }
      w->a[j++]=c;
      if(val[c->lits[0]]==-1){ while(i<w->n) w->a[j++]=w->a[i++]; w->n=j; qhead=trailN; return c; }
      enq(c->lits[0],c);
    } w->n=j; }
  return 0; }
static void bump(int v){ act[v]+=inc; if(act[v]>1e100){ for(int i=1;i<=nV;i++) act[i]*=1e-100; inc*=1e-100; } if(hpos[v]>=0) hup(hpos[v]); }
static int analyze(Cl*confl){ int cnt=0, p=-1, idx=trailN-1, bt=0; learntN=1;
  do{ for(int j=(p==-1?0:1); j<confl->size; j++){ int q=confl->lits[j], v=VAR(q);
        if(!seen[v] && lvl[v]>0){ seen[v]=1; bump(v); if(lvl[v]>=nLim) cnt++; else { learnt[learntN++]=q; if(lvl[v]>bt) bt=lvl[v]; } } }
      while(!seen[VAR(trail[idx])]) idx--; p=trail[idx]; idx--; confl=reason[VAR(p)]; seen[VAR(p)]=0; cnt--; }while(cnt>0);
  learnt[0]=NEG(p); for(int i=1;i<learntN;i++) seen[VAR(learnt[i])]=0; return bt; }
static void cancel(int level){ if(nLim<=level) return; for(int i=trailN-1;i>=lim[level];i--){ int l=trail[i], v=VAR(l); phase[v]=(l&1); val[l]=val[NEG(l)]=0; hins(v);} trailN=lim[level]; qhead=trailN; nLim=level; }
static Cl* mk(int*ls,int n){ Cl*c=malloc(sizeof(Cl)+sizeof(int)*n); c->size=n; memcpy(c->lits,ls,sizeof(int)*n); return c; }
int main(int argc,char**argv){ FILE*f=fopen(argv[1],"r"); int nC; char buf[256];
  for(;;){ int ch=fgetc(f); if(ch=='c'){ fgets(buf,256,f);} else if(ch=='p'){ fscanf(f," cnf %d %d",&nV,&nC); break; } }
  int n2=2*(nV+1); val=calloc(n2,1); lvl=calloc(nV+1,sizeof(int)); trail=malloc(sizeof(int)*(nV+1)); lim=malloc(sizeof(int)*(nV+1)); reason=calloc(nV+1,sizeof(Cl*));
  wat=calloc(n2,sizeof(Vec)); act=calloc(nV+1,sizeof(double)); phase=malloc(nV+1); memset(phase,1,nV+1); seen=calloc(nV+1,1);
  heap=malloc(sizeof(int)*(nV+1)); hpos=malloc(sizeof(int)*(nV+1)); learnt=malloc(sizeof(int)*(nV+1));
  for(int v=1;v<=nV;v++){ hpos[v]=-1; act[v]=1.0/(v+1); } for(int v=1;v<=nV;v++) hins(v);
  int *tmp=malloc(sizeof(int)*(nV+1)), tn=0, x, unsat=0;
  while(fscanf(f,"%d",&x)==1){ if(x!=0){ tmp[tn++]= x>0? 2*x : 2*(-x)+1; continue; }
    if(tn==0) unsat=1; else if(tn==1){ if(val[tmp[0]]==-1) unsat=1; else if(val[tmp[0]]==0) enq(tmp[0],0); }
    else { Cl*c=mk(tmp,tn); vpush(&wat[c->lits[0]],c); vpush(&wat[c->lits[1]],c); } tn=0; }
  long conflicts=0, rlim=100, rc=0;
  if(!unsat) for(;;){ Cl*c=propagate();
    if(c){ if(nLim==0){unsat=1;break;} conflicts++; rc++; int bt=analyze(c); cancel(bt);
      if(learntN==1) enq(learnt[0],0); else { int mi=1; for(int i=2;i<learntN;i++) if(lvl[VAR(learnt[i])]>lvl[VAR(learnt[mi])]) mi=i; int t=learnt[1]; learnt[1]=learnt[mi]; learnt[mi]=t;
        Cl*n=mk(learnt,learntN); vpush(&wat[n->lits[0]],n); vpush(&wat[n->lits[1]],n); enq(learnt[0],n); }
      inc*=1.0/0.95; }
    else { if(rc>=rlim){ rc=0; rlim=rlim*3/2; cancel(0); continue; }
      int v=-1; while(hN>0){ int z=hpop(); if(val[2*z]==0){v=z;break;} } if(v<0) break;
      lim[nLim++]=trailN; enq(2*v+(phase[v]?1:0),0); } }
  fprintf(stderr,"c conflicts %ld\n",conflicts);
  if(unsat){ printf("s UNSATISFIABLE\n"); return 20; }
  printf("s SATISFIABLE\nv"); for(int v=1;v<=nV;v++) printf(" %d", val[2*v]==1? v : -v); printf(" 0\n"); return 10; }
