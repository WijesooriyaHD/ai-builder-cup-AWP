class BlogPost {
  final String id;
  final String title;
  final String excerpt;
  final String category;
  final int readTimeMinutes;
  final String imageUrl;
  final String content;
  final BlogSurvey? survey;

  BlogPost({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.category,
    required this.readTimeMinutes,
    required this.imageUrl,
    required this.content,
    this.survey,
  });
}

class BlogSurvey {
  final String question;
  final List<String> options;

  BlogSurvey({
    required this.question,
    required this.options,
  });
}

// Wellness-focused reads for the Explore tab.
List<BlogPost> getBlogPosts() {
  return [
    BlogPost(
      id: '1',
      title: 'The Science of a Calmer Mind',
      excerpt: 'How just a few minutes of daily mindfulness can rewire your stress response.',
      category: 'Mindfulness',
      readTimeMinutes: 4,
      imageUrl: '🧘',
      content: '''
# The Science of a Calmer Mind

Mindfulness isn't about emptying your mind or sitting perfectly still for an hour. It's simply the practice of noticing the present moment without judging it. And the research is clear: **a few minutes a day can meaningfully lower stress and improve focus.**

## What Happens in Your Brain

When you're stressed, your amygdala—the brain's alarm system—goes into overdrive. Regular mindfulness practice has been shown to calm that alarm and strengthen the areas linked to attention and emotional balance.

## A 3-Minute Starting Point

You don't need an app or a cushion. Try this:
1. Sit comfortably and close your eyes.
2. Notice your breath, without changing it.
3. When your mind wanders (it will), gently return to the breath.

That "returning" is the whole exercise. Every time you notice and come back, you're building the skill.

## Make It Stick

Attach it to something you already do—right after brushing your teeth, or before your first coffee. Consistency beats duration.

**Start with three minutes today.** Your nervous system will thank you.
''',
      survey: BlogSurvey(
        question: 'When do you feel most stressed?',
        options: [
          'Mornings',
          'During work',
          'Evenings',
          'Right before sleep',
        ],
      ),
    ),
    BlogPost(
      id: '2',
      title: 'Sleep Is a Superpower',
      excerpt: 'Why quality rest is the foundation of every wellness goal—and how to protect it.',
      category: 'Sleep',
      readTimeMinutes: 5,
      imageUrl: '🌙',
      content: '''
# Sleep Is a Superpower

We treat sleep as the first thing to sacrifice when life gets busy. But sleep isn't downtime—it's when your body repairs, your brain consolidates memories, and your emotions reset. **Protecting your sleep protects everything else.**

## The Cost of Cutting Corners

Even a single night of poor sleep can raise stress hormones, dull focus, and increase cravings. Over time, chronic sleep debt affects mood, immunity, and recovery.

## Build a Wind-Down Routine

Your body loves signals. An hour before bed:
- Dim the lights to cue melatonin.
- Put screens away, or switch to night mode.
- Do something low-key—stretching, reading, or slow breathing.

## Keep It Consistent

Going to bed and waking at similar times—even on weekends—keeps your internal clock steady. Consistency often matters more than the exact number of hours.

## If You Can't Sleep

Don't lie there frustrated. Get up, keep the lights low, and do something calming until you feel drowsy. Bed should mean rest, not stress.

**Guard your rest like the superpower it is.**
''',
      survey: BlogSurvey(
        question: 'How would you rate your sleep lately?',
        options: [
          'Great',
          'Okay',
          'Restless',
          'Struggling',
        ],
      ),
    ),
    BlogPost(
      id: '3',
      title: 'Movement You Actually Enjoy',
      excerpt: 'The best exercise isn\'t the "perfect" one—it\'s the one you\'ll keep coming back to.',
      category: 'Movement',
      readTimeMinutes: 3,
      imageUrl: '🏃',
      content: '''
# Movement You Actually Enjoy

Exercise doesn't have to mean punishing workouts or a gym you dread. Your body is designed to move, and the healthiest movement is the kind you genuinely look forward to. **Enjoyment is what makes it last.**

## Ditch the "No Pain, No Gain" Myth

You don't need to be sore or exhausted to benefit. Walking, dancing, gardening, swimming, gentle yoga—it all counts. What matters is showing up regularly.

## Find Your Kind of Movement

Ask yourself:
- Do I prefer being outdoors or indoors?
- Alone or with others?
- Calm and slow, or upbeat and energetic?

Let your answers guide you toward something sustainable.

## Small Doses Add Up

Three 10-minute walks can be as valuable as one long session. Stack movement into your day: take the stairs, stretch between tasks, walk while you take a call.

## Listen to Your Body

Some days call for intensity; others call for rest or gentle recovery. Tuning in—not pushing through—is what keeps you moving for life.

**Find the movement that feels like a gift, not a chore.**
''',
      survey: BlogSurvey(
        question: 'What kind of movement do you enjoy most?',
        options: [
          'Walking or hiking',
          'Strength training',
          'Yoga or stretching',
          'Dance or cardio',
        ],
      ),
    ),
    BlogPost(
      id: '4',
      title: 'Eating for Energy, Not Rules',
      excerpt: 'Nourishment over restriction: a gentler, more sustainable way to fuel your body.',
      category: 'Nutrition',
      readTimeMinutes: 4,
      imageUrl: '🥗',
      content: '''
# Eating for Energy, Not Rules

Wellness culture is full of rigid food rules—cut this, avoid that, never eat after 7. But strict rules often backfire, leading to stress and guilt. A gentler approach is to focus on **how food makes you feel and how it fuels your day.**

## Add Before You Subtract

Instead of obsessing over what to remove, think about what to add:
- More colorful vegetables
- More water throughout the day
- More protein and fiber to stay full and steady

Crowding in the good stuff naturally shifts the balance.

## Notice Your Energy

Food affects mood and focus. Pay attention: which meals leave you energized, and which leave you sluggish? Let that awareness guide your choices—no calorie math required.

## Eat With Attention

Slow down. Put the phone away for one meal. Notice flavors and textures. Eating mindfully helps you feel satisfied with less effort.

## Be Kind to Yourself

One indulgent meal won't undo your health, just as one salad won't fix everything. Consistency and self-compassion matter more than perfection.

**Fuel your body with care, not control.**
''',
      survey: BlogSurvey(
        question: 'What\'s your biggest nutrition goal?',
        options: [
          'More energy',
          'Eating more mindfully',
          'Staying hydrated',
          'Less stress around food',
        ],
      ),
    ),
    BlogPost(
      id: '5',
      title: 'The Power of Self-Compassion',
      excerpt: 'Being kind to yourself isn\'t soft—it\'s one of the strongest wellness habits there is.',
      category: 'Mental Health',
      readTimeMinutes: 5,
      imageUrl: '💗',
      content: '''
# The Power of Self-Compassion

Many of us talk to ourselves in a way we'd never talk to a friend—harsh, critical, unforgiving. But research shows that **self-compassion, not self-criticism, is what actually helps us grow, recover, and stay motivated.**

## What Self-Compassion Really Means

It has three parts:
1. **Kindness** instead of judgment when you struggle.
2. **Common humanity**—remembering that everyone has hard days.
3. **Mindfulness**—acknowledging pain without exaggerating or suppressing it.

## Why It Works

Self-criticism triggers your stress response, making it harder to think clearly and bounce back. Self-compassion calms that response, freeing you to learn and try again.

## A Simple Practice

Next time you slip up, pause and ask: *What would I say to a friend in this situation?* Then offer those same words to yourself.

## It's Not About Lowering Standards

Being kind to yourself doesn't mean giving up on your goals. It means supporting yourself through setbacks so you can keep going—sustainably.

**Treat yourself like someone you're rooting for.**
''',
      survey: BlogSurvey(
        question: 'How is your inner voice most days?',
        options: [
          'Supportive',
          'Neutral',
          'Often critical',
          'Very harsh',
        ],
      ),
    ),
    BlogPost(
      id: '6',
      title: 'Breathe Your Way to Calm',
      excerpt: 'Your breath is a built-in tool for stress relief—here\'s how to use it anywhere.',
      category: 'Stress Relief',
      readTimeMinutes: 3,
      imageUrl: '🌬️',
      content: '''
# Breathe Your Way to Calm

When stress hits, your breathing becomes fast and shallow, signaling danger to your brain. The good news: you can reverse that signal. **Slowing your breath tells your nervous system that you're safe.**

## Why Breathwork Works

Long, slow exhales activate the parasympathetic nervous system—your body's "rest and digest" mode. Within a minute or two, your heart rate slows and tension eases.

## Try Box Breathing

A favorite of athletes and first responders:
1. Inhale for a count of 4.
2. Hold for 4.
3. Exhale for 4.
4. Hold for 4.

Repeat for four rounds. That's it.

## The 4-7-8 Method

For winding down at night:
- Inhale through your nose for 4.
- Hold for 7.
- Exhale slowly through your mouth for 8.

## Use It Anywhere

Before a meeting, in traffic, or lying awake at 2 a.m.—your breath is always with you. No equipment, no app, no cost.

**The calm you need is one slow exhale away.**
''',
      survey: BlogSurvey(
        question: 'When would breathwork help you most?',
        options: [
          'Before stressful moments',
          'During anxiety',
          'To fall asleep',
          'To refocus during the day',
        ],
      ),
    ),
    BlogPost(
      id: '7',
      title: 'Pilates for Beginners: Start With Your Core',
      excerpt: 'A gentle introduction to Pilates and why it builds strength from the inside out.',
      category: 'Pilates',
      readTimeMinutes: 4,
      imageUrl: '🤸',
      content: '''
# Pilates for Beginners: Start With Your Core

Pilates has a reputation for being tough, but at its heart it's a mindful, low-impact practice that builds strength, stability, and body awareness. **You don't need special equipment or flexibility to begin—just your body and a bit of floor space.**

## What Makes Pilates Different

Rather than chasing big movements, Pilates focuses on control, precision, and breath. Every exercise starts from your core—the deep muscles around your abdomen, back, and pelvis that support everything you do.

## Three Moves to Try Today

1. **The Hundred (modified):** Lie on your back, knees bent, and pump your arms gently while breathing steadily. Builds core endurance.
2. **Pelvic Curl:** Slowly roll your spine off the mat one vertebra at a time, then lower back down. Great for spinal mobility.
3. **Single-Leg Stretch:** Draw one knee in while extending the other leg, then switch. Trains coordination and control.

## Breathe With Every Movement

In Pilates, breath drives the motion. Inhale to prepare, exhale as you engage. This connection is what turns simple movements into deep, effective work.

## Go Slow to Go Far

Quality beats quantity. A few controlled reps will do more than rushing through many. **Start gentle, stay consistent, and let your core wake up.**
''',
      survey: BlogSurvey(
        question: 'What draws you to Pilates?',
        options: [
          'Core strength',
          'Better posture',
          'Low-impact movement',
          'Injury recovery',
        ],
      ),
    ),
    BlogPost(
      id: '8',
      title: 'Why Posture Is Your Secret to Feeling Better',
      excerpt: 'How Pilates-inspired alignment eases tension and boosts everyday energy.',
      category: 'Pilates',
      readTimeMinutes: 3,
      imageUrl: '🩰',
      content: '''
# Why Posture Is Your Secret to Feeling Better

We spend hours hunched over phones and desks, and our bodies pay the price—tight shoulders, achy backs, low energy. Pilates puts alignment at the center of everything, and **better posture can transform how you feel day to day.**

## Posture Isn't About Standing Stiff

Good posture is dynamic and relaxed, not rigid. It's about stacking your body so muscles share the load instead of a few doing all the work.

## A Quick Alignment Reset

Try this any time you've been sitting:
- Roll your shoulders back and down.
- Lengthen through the crown of your head.
- Gently draw your lower ribs in.
- Take a slow breath into your back and sides.

## The Ripple Effect

When your body is aligned, you breathe more fully, move more freely, and often feel more confident. Small adjustments, repeated often, retrain your default posture over time.

## Build It Into Your Day

Set a reminder to reset your posture a few times daily. Pair it with breathwork for an instant reset. **Stand tall, breathe deep, and feel the difference.**
''',
      survey: BlogSurvey(
        question: 'Where do you hold the most tension?',
        options: [
          'Neck and shoulders',
          'Lower back',
          'Hips',
          'All over',
        ],
      ),
    ),
    BlogPost(
      id: '9',
      title: 'Yoga for Every Body',
      excerpt: 'Forget the pretzel poses—yoga is about connection, not contortion.',
      category: 'Yoga',
      readTimeMinutes: 4,
      imageUrl: '🕉️',
      content: '''
# Yoga for Every Body

If images of impossible poses have kept you from trying yoga, here's the truth: **yoga is for every body, at every level.** It's a practice of connecting movement, breath, and awareness—not a competition to touch your toes.

## More Than Flexibility

Yoga builds strength, balance, and calm. It can ease stress, improve sleep, and help you feel more at home in your body. Flexibility comes gradually, as a side effect—not a requirement.

## Foundational Poses to Explore

1. **Mountain Pose:** Simply standing tall and grounded. The foundation of everything.
2. **Cat-Cow:** On all fours, arch and round your spine with your breath. Wonderful for stiff backs.
3. **Child's Pose:** A resting pose you can return to any time you need a pause.

## Let the Breath Lead

In yoga, the breath is your anchor. Moving slowly with each inhale and exhale turns simple stretches into a calming, meditative practice.

## Honor Where You Are

Use props, modify poses, and rest when you need to. There's no "perfect" version—only what feels right for your body today.

**Roll out a mat, take a breath, and begin exactly where you are.**
''',
      survey: BlogSurvey(
        question: 'What would you love to get from yoga?',
        options: [
          'Less stress',
          'More flexibility',
          'Strength and balance',
          'A calmer mind',
        ],
      ),
    ),
    BlogPost(
      id: '10',
      title: 'A Simple Evening Yoga Wind-Down',
      excerpt: 'Five gentle poses to release the day and prepare your body for deep rest.',
      category: 'Yoga',
      readTimeMinutes: 3,
      imageUrl: '🌾',
      content: '''
# A Simple Evening Yoga Wind-Down

After a long day, a few minutes of gentle yoga can signal your body that it's time to rest. This calming sequence needs no experience—just a quiet spot and slow, steady breathing. **Consider it a gift to your future, well-rested self.**

## The Sequence

Move slowly, holding each pose for 5 to 10 breaths.

1. **Seated Forward Fold:** Sit with legs extended and gently fold forward. Releases the back and hamstrings.
2. **Reclined Twist:** Lying down, drop both knees to one side, then the other. Eases the spine.
3. **Legs Up the Wall:** Rest your legs vertically against a wall. Deeply relaxing for tired legs and mind.
4. **Butterfly Fold:** Soles of the feet together, fold forward gently. Opens the hips.
5. **Final Rest:** Lie flat, arms relaxed, and simply breathe for a minute or two.

## Breathe It Out

With each exhale, imagine releasing a bit of the day's tension. Let your body grow heavier and softer.

## Keep It Screen-Free

Dim the lights and leave your phone in another room. This is your transition into rest.

**End your day soft, slow, and calm.**
''',
      survey: BlogSurvey(
        question: 'What time do you usually wind down?',
        options: [
          'Right after dinner',
          'An hour before bed',
          'Just before sleep',
          'I rarely wind down',
        ],
      ),
    ),
  ];
}
