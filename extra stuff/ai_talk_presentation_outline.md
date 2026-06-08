
# AI Lightning Talk Outline
_Note: A gameplay video of Critter Quitters Pest Control will run continuously in the background for the duration of the talk_

## Introduction: The three core objectives for the project
Project was perfect chance to recreate a favorite browser game from 20+ years ago
- working with new game engine
- writing zero lines of code manually
- establishing automated deployment pipeline

## Section 1: The Setup (~1m)
I decided to use Godot and GDScript
- Primary motivation the desire to work with new platform and tech stack
- Strong preference for open-source
- Claude definined folder structures and full source control integration

## Section 2: The Role (~1m)
- Acted strictly as game designer
- Described desired logic, reviewed generated code, and made structural decisions
- Claude generated the initial art assets, I refined and tweaked
- Debugging was surprisingly seamless — feeding error logs back into the system typically resulted in a first-try fix

## Section 3: The Pipeline Surprise (~2m)
- Needed automated build and deployment pipeline that could be triggered externally
- Described desired outcome to Claude, which then:
	- defined necessary toolchain (GitHub Actions, Firebase)
	- walked me through the setup process step-by-step
	- handled all intricate details of connecting the systems
- Result was a fully functional deployment process that can push a signed Android APK to my phone every time I push a commit

## Section 4: The Closer (30s)
- Letting AI handle code allowed me to focus entirely on the game's design and art
- making it possible to build something functional in a completely unfamiliar technology
