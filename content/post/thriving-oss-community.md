+++
title = "How to Build a Thriving Open-source Community"
draft = false
date = 2017-11-28T00:00:00Z
tags = [
]
categories = [
]
description = "Some of the initial ideas, tactics, and approaches that we are employing and believe will drive the success of our community."
author = "cblake"
+++

 
Building a community of developers was one of the key motivations that led Wallaroo Labs to open-source our distributed data engine, Wallaroo.
 
But it’s not always easy. There are millions of public, open-source repositories on GitHub. How do you stand out from the crowd and build a thriving developer community around your project?
 
The plan we developed to grow our community was the same as the one we used with our open-source code: put our best foot forward, then learn and adjust as we go along.
 
In this post, I will share some of the initial ideas, tactics, and approaches that we are employing and believe will drive the success of our community.
 
## Set Goals and Measure Results
 
The beauty of GitHub is that it brings together developers from all over the world. That is a huge opportunity! How will you benefit from this collection of potential advisors, critics, contributors, and customers?
 
Start by considering your own repository. What are your critical metrics, and how can you measure them?
 
If you don’t know what you hope to achieve, then what’s the point of opening up your code to the public at all? You might as well keep it closed. Identify your main goal. Is it software downloads?  Getting developers to contribute to your project? Adding names to your developer mailing list?
 
All are reasonable objectives, but they only help you if you measure their results.
 
It might take some setup and development efforts to put a results-tracking mechanism in place. Even then, not everything you want to achieve will be measurable. Be sure you get your head around measurement early in the process, so you can create a plan and adapt as things change.
 
At Wallaroo Labs, one of the most important metrics is the "Unique clones" number (included in the Traffic Statistics section of the GitHub repo reports). This metric gives us a good idea of our daily download activity.  We also log all of the GitHub repository statistics on a regular basis. Stars, Forks, Issues, Pull Requests – these statistics give us usage “signals."
 
Estimating future marketing activities and product evolution allows us to put a straw-man plan in place, giving us a way to measure our progress against any plan.
 
## Be Transparent with Developers
 
Developers don’t appreciate being misled. We believe that being open and honest about the state of our software and our progress will help build loyalty in our community.
 
And we practice what we preach. We know that our product isn’t perfect, our mission, to democratize data processing by removing the barriers of complexity, cost, performance, and language support, will keep our team busy for the foreseeable future as we try to get it there. In the meantime, we share our shortcomings. Open-source means open-obstacle too.

Here’s an example: Autoscaling is a feature that we have a lot of clients asking for.  Here is our status regarding autoscaling within Wallaroo:

Wallaroo was built to provide programmers with a scale-agnostic API. New workers can be added to a running Wallaroo cluster. Existing workers can be removed from a running cluster. Wallaroo will adapt to both scenarios by redistributing work and continuing to process data without having to restart the cluster. We aren't quite there yet with a full-featured, rock-solid autoscaling, but we are close.

It would be dishonest to claim autoscaling was any stronger than it is. In this community, exaggerating your code is a problem. Deception will make you a pariah.

 
Additionally, we maintain [an up-to-date roadmap](https://github.com/WallarooLabs/wallaroo/blob/master/ROADMAP.md) that provides high-level visibility into where we are taking the product.

## Showcase the Technology
 
Nothing will drive attention to your project more than your tech.
 
The team at Wallaroo Labs has worked hard to make our technology shine. We incorporate the best ideas from academic papers, existing distributed computing platforms, and customer feedback to make a data engine that will help businesses easily build data applications now and in the future.
 
For us, the tech is front and center. Our website and user documentation explore the technical details of Wallaroo. We also write [deep-dive blog posts](https://blog.wallaroolabs.com/) on topics we think the community would find interesting. Since we have open-sourced Wallaroo, our blog has been getting an increase of traffic. The tech is our number one referral!
 
Other developer communities, like Hacker News, also drive a good deal of traffic to our blog, showing us that our tech-centric message resonates with other developers.
 
We believe putting our technology front and center will help us build awareness and user adoption. Our technology is our best marketing.  
 
## Make it easy-to-use
 
Excellent documentation is the first step in making your software easy-to-use.  Make sure you have readmes, the API, and supporting technical documentation in place.  All of the documentation that we provide is peer-reviewed by the entire development team to make sure that everything is clear. We also have someone from outside the company review all new documentation before we make it available.
 
To create great docs, you must understand your reader.  How technical are they?  Have they used similar software in the past?  What comparisons can you use to make this easier to learn?
 
Our documentation is written assuming that the reader has a base-level understanding of streaming systems and distributed systems.  Where appropriate, we may point people to [other resources](http://www.wallaroolabs.com/community/talks) for a broader understanding of distributed systems.
 
## Encourage participation
 
When users are downloading and trying your software, things are starting to come together. Now, you need to encourage them to participate directly.
 
Make sure that everyone knows your project is a safe place to get involved without fear of personal criticism. At Wallaroo Labs, our commitment to a positive open-source experience is embodied in our [Code of Conduct](http://www.wallaroolabs.com/community/code-of-conduct):
 
In the interest of fostering an open and welcoming environment, we as contributors and maintainers pledge to make participation in our project and our community a harassment-free experience for everyone, regardless of age, body size, disability, ethnicity, gender identity and expression, level of experience, nationality, personal appearance, race, religion, or sexual identity and orientation.
 
Once you’ve laid out the ground rules, here are some ways to encourage participation:
 
Establish communications channels using tools like Slack, mailings lists, IRC, etc.  
Make it easy for developers to ask and answer questions.  ([IRC](https://webchat.freenode.net/?channels=#wallaroo) is one of the primary channels we use. There is usually one of our developers "lurking" around there somewhere.)
Identify issues for first-timers
 
Experienced open-source developers know how to jump right in, tackle issues, and make pull requests.  Other interested users might not have as much experience working on an open-source project.  It's helpful to encourage these beginners by steering them towards "low hanging fruit".  
 
Documentation edits are a great way to gain experience in an open source project.  We also label issues on GitHub as "good first issue" or help wanted" to identify reasonable beginner tasks.
 
## Be available to assist the community.
 
Early on in your product’s development, user input is critical. Their broad stroke feedback can change major features that you may have not realized even needed attention. Getting the opinions of your users reveals whether your code is meeting its big-picture goals.
 
From there, you can start narrowing in on the tinier problems.
 
The other benefit of being available to assist your users is that they begin to trust you. The interactions build relationships that let your community thrive.
 
We love watching our community grow, so the team at Wallaroo Labs is making itself available on a variety of channels to make sure it easy possible for users to communicate with us.
 
The fastest way to get in contact with us is over IRC.  We have an IRC channel set up at [#wallaroo at Freenode](https://webchat.freenode.net/?channels=#wallaroo). Our developers hang around on that channel a lot, so hit them up if you have any questions or comments.
 
We also have a [developer mailing list](https://groups.io/g/wallaroo) for groups.io that provides ongoing information. Anyone who subscribes to that list receives all Wallaroo announcements, including public releases and information about our latest blog posts.  We also encourage other community users to jump in and offer assistance.
 
If you are interested in speaking to us about how Wallaroo could help solve your particular problems, you can jump the queue and schedule a call with me directly by [clicking here](https://calendly.com/chuckb/wallaroo-user-interview).
 
You can see that maintaining availability is really important to us. That’s why [we’re hiring a full-time developer evangelist](http://careers.wallaroolabs.com/apply/99yvBVfMGM/Developer-Evangelist) to contact Wallaroo developers, identify use cases, and get early feedback on the product.  We want to get information in front of developers and conduct as many of these user interviews as possible!  
 
## Talk to Users

In addition to user interviews, we are continually attending conferences and meetups to build awareness and find the right audience for Wallaroo.
 
Even when we aren’t presenting, attending these events and speaking to developers directly is a great way to get feedback. Face-to-face interactions often help us build a better understanding of the problems and challenges that developers face.
 
## Listen to feedback

We are proud of Wallaroo and have put blood, sweat, and tears into the product.  Naturally, it can be difficult to hear criticism.
 
Our job is to make sure that we listen to feedback, both the good and the bad.  Some of the most useful information can be found in the seemingly hard criticism.
 
After a [recent blog post](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/) on our Python API, [we received some comments](https://news.ycombinator.com/item?id=15457343) that our API needed to be "more Pythonic." We listened to that feedback, spoke to many users directly, and incorporated their ideas into our roadmap for the Python API (updated version coming later this year).
 
If we closed our ears to the criticism of our users, we would be betraying all the work and feedback they gave us.
 
## Conclusion
 
We believe that building a great user community is possible if you set measurable goals, are honest about your code, treat your community with respect, and engage them often. The community we have built around Wallaroo has helped us get closer to our long-term goal of making this the best tool that developers building distributed data processing applications can possibly get.
 
These are just some of the ways that we are going about it, and we expect to incorporate even more ideas into our process as we continue to hear your feedback and learn from our mistakes. 

Let us know what you think would bring you into our community by sharing this post with your feedback on social media.
 
As I mentioned earlier, we are currently looking to hire a full-time Developer Evangelist in the SF Bay Area to help us continue to build our community.  If you are interested, you can [check out the job posting here](http://careers.wallaroolabs.com/apply/99yvBVfMGM/Developer-Evangelist).
