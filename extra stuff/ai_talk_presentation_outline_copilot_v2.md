# 🔥 AI Lightning Talk — 5‑Minute Outline

_Note: Gameplay video of **Critter Quitters Pest Control** loops in background._

I wanted to share a mobile game I've been building in my free time using Claude Code.

## Background
- I have spent time previously building very small games in Unity and GameMaker Studio
- I enjoy the process of game design
- I wanted to recreate a browser game I really enjoyed from 20+ years ago

## Goals (10–15s)

**Three primary goals:**
- Use an unfamiliar engine  
- Write zero code  
- Build a fully automated deployment pipeline  


## The Setup (_Choosing the Tools_) (~1 min)
**Why Godot + GDScript**
- Wanted a fresh tech stack  
- Preference for open‑source

**How AI fit in immediately**
- Claude generated folder structure + project scaffolding  
- Full Git integration set up automatically  


## My Role (~1 min)
**My constraints:**
- I acted purely as **game designer**, not programmer  

**My workflow:**
- Describe logic → AI generates code → I review + adjust  
- AI produced initial art → I refined  
- Debugging became: paste error → get fix → move on  


## The Pipeline Surprise (_The Big Win_) (~2 min)
**The challenge:**  
Needed an automated build + deployment pipeline triggered externally.

**The process:**
- I described the full deployment process I wanted  
- Claude:  
  - Chose the toolchain (GitHub Actions + Firebase)  
  - Walked me through setup (_in and out of claude_)
  - Generated configs + scripts  
  - Connected everything end‑to‑end
  - Generated documentation

**End result:**  
A pipeline that **pushes a signed Android APK to my phone every time I commit**.


## In Closing (30s)
**Key takeaway:**  
- AI handled the code so I could focus on **design**, **art**, and **game feel**.
- It was like having an experienced, professional developer quickly implementing every change I described.