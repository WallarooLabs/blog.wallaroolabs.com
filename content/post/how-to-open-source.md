+++
title = "Open-source your startup’s code in 60 days"
date = 2017-11-02T07:45:00-04:00
draft = false
author = "vidjain"
description = "Opening up the source of your startup's code isn't easy; here's what we learned."
tags = [
    "open source",
    "legal",
    "strategy",
    "marketing",
    "business"
]
categories = [
    "Our Startup Experience"
]
+++
I’m Vid Jain, CEO & Founder of [Wallaroo Labs](https://www.wallaroolabs.com/). I’m writing today to tell you about how we open-sourced Wallaroo, our software framework for data processing, and the lessons we learned along the way. Our engineering team was experienced at writing great software, but now we faced a new set of challenges. None of us had open-sourced enterprise software before. There are ten key things we did that overcame the barriers and got all our code into the open in just 60 days.

We had been hard at work for 18 months on Wallaroo, with the goal of open-sourcing it. For 18 months we had many serious discussions as a group about our open-source plans. Then we got funding from several VCs with open-source as a core business strategy, so now we had to do it, and do it well and fast. I feel confident we did a great job. At a recent board meeting, one investor said, “Hey, Vid, that’s a great story.”

I wanted to share this below. Be warned it’s a LOT more effort than might be expected, and balancing our goal of building a developer community with our commercial interests created many heated discussions. I hope this post is helpful and that you check out Wallaroo at [WallarooLabs.com](https://www.wallaroolabs.com/). It lets you build and operate fast data, big data and AI applications that deploy rapidly, scale automatically and run at very low-cost. Our Github repository for [native Python](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/) is at [https://github.com/WallarooLabs/wallaroo](https://github.com/WallarooLabs/wallaroo), and our community page is [here](https://www.wallaroolabs.com/community). Please try it out and give us feedback.

## 1. Teamwork is Key.

The ultimate responsibility fell on me, but it goes without saying that you need to keep your engineers involved in the process. Early on I formed a close collaboration with my Head of Engineering and our Head of Marketing, which was critical.  We scheduled specific meeting times each week to cover the various deliverables and any outstanding issues.

## 2. Don’t re-invent the wheel.

Get advisors who've done it before and look at similar companies and their strategies. The most important question I got from an advisor was: “What’s your goal in open-sourcing?” For example, if your goal is to make $100MM a year, that leads to a different strategy than aiming for a huge market share. Expect the process of answering questions and getting feedback from your advisors to be iterative. Meet frequently with your team and devote significant time to understanding what you want to achieve and how you might go about it.

## 3. Hire a software-licensing attorney with relevant experience.

We wanted to create a commercial business, and I didn’t want to base critical decisions on just my knowledge. Ask around for recommendations for attorneys, talk to several, and go with experience and what your gut tells you. I spoke to five attorneys before getting the same recommendation from both Cockroach Labs and from an investor in MongoDB. We went with an attorney from Gunderson Dettmer that a group of us liked, and it turned out great.


## 4. Make sure executive, marketing, and engineering are in agreement about goals.

Sounds obvious, but it’s effort to get there. Often, you’re all using the same terms but mean different things. Eventually, we were able to agree on our goals and the language we used to describe them. For example, what do you mean when you say “open-source” vs. “community license,” or what’s actually in the open-source version of the software. Does it include, e.g., the tools you use to test your software or the UI you use to monitor performance?

## 5. Determine what customers will pay you for.

If your goal is to generate revenue, this is a key question, and the first answer may not be right. You have to figure out who your paying customers are, their use-cases, and where you fit in. For us, our customers are startups, medium and large enterprises, and cloud-based service providers. Our key value is in significantly reducing the complexity and cost of deploying data applications at large scale.

## 6. Design a licensing strategy to lets many developers use it, with dials for monetizing.

Again, if your goal is commercial, then you will have to balance two drivers. On the one hand, you want to get as many developers as possible trying and using your product. On the other, you want users who are getting the most value to give some of that back to you as revenue. Where to draw that line between the two is going to involve experimentation (unless your business is solely a support business). So build in some dials that you can turn. In our case, one dial is the number of servers that Wallaroo is deployed with for advanced features.

## 7. Work on your licenses and support agreements.

Now that you’ve decided on what you want to fully open-source, and what you want to make money on, you’ve got a lot of work. In addition to the license for the open-source part, you need a contributor’s agreement, a community or commercial software license, and a commercial use and support agreement. This is where that great attorney you hired is instrumental - but don’t just leave it up to her. Ask a lot of questions and make sure it makes sense to your team.

## 8. Work on improving user experience.

Outside developers are going to need excellent documentation, examples, tutorials, and easy installation. Make sure you’ve thought these through and don’t hesitate to ask friends to give critical feedback. We had an outside developer evangelist go through our website and documents, and we had a soft-launch where developer friends gave us feedback on installation and using the software.

## 9. Work on the website and your community page.

You need to explain what your software does and give access to all the [supporting materials](https://www.wallaroolabs.com/community). Don’t leave this to the end because your first version of everything will need to be reworked. In our case, we had constant revisions over 3 weeks. And what’s the goal? Is it to drive visitors to your community page or documentation, is it to get developers to your GitHub repository, or is to have developers spend a lot of time on your website?

## 10. Cleanup code, refactor if needed, add tags.

Expect to devote a significant amount of developer effort to this. In our case, we had to decide on a file-by-file basis what license the code was getting, and we had to move the code into a different directory structure. Once done, check again. We had two engineers working on this for a month, and it impacted other projects (it’s hard to change the engine in a moving car).

## Ok, now what?

If you think you’ve gotten everything perfect, you’ve spent too much time on it. Once it’s out in the open, you’re going to get a ton of feedback on everything from your website to your documentation, to use-cases, and the actual product. Not everything will line up with what you think is perfect.

For us, our understanding of what we meant when we said “open-source” evolved to include not just software released under a standard open-source license, but also code available under a more restrictive license. Initially we released the core Wallaroo product under Apache 2.0 and additional advanced features under the Wallaroo community license, but now all of Wallaroo is available under Apache 2.0.

My colleague Chuck Blake will cover what you need to do once it’s open-source in an upcoming post - you’ve just gotten started.

## Give Wallaroo a try

We’re excited to start working with our friends in the open-source community and new commercial partners.

If you are interested in getting started with Wallaroo, head over to [our website and get started](https://www.wallaroolabs.com/community). And if this post sparked your curiosity and you want to talk more, please contact me at [Vid.Jain@WallarooLabs.com](mailto:Vid.Jain@WallarooLabs.com).
