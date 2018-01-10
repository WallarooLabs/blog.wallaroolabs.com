+++
title = "Serverless, Scale-Independent Processing, and Wallaroo"
date = 2018-01-10
draft = false
author = "vidjain"
description = "Our open-source framework, Wallaroo, shares many high-level goals as the existing serverless frameworks, but is also different in key areas and thus better suited for many use-cases."
tags = [
    "open source",
    "wallaroo",
    "strategy",
    "marketing",
    "business",
    "serverless",
    "scale-independence",
    "scaling"
]
categories = [
    "Our Startup Experience"
]
+++

Serverless is most commonly thought of as pieces of code executed in a stateless container, e.g. AWS Lambda and Functions-as-a-Service. Our open-source framework, [Wallaroo](https://www.wallaroolabs.com/community), shares many high-level goals as the existing serverless frameworks, but is also different in key areas and thus better suited for many use-cases. In this post, I want to introduce an expansive vision of serverless which is about letting developers focus simply on implementing the business logic without worrying about scale, servers, or infrastructure issues. Under this vision, Wallaroo is “serverless for high-performance data processing” that can run anywhere.

Let’s explore what I mean in more detail. We started Wallaroo Labs with the mission to make it as simple as possible for firms to build and operate data applications without worrying about scale or resiliency. We launched Wallaroo just over three months ago and have talked to many developers, data scientists, CTOs, and even investors, about  [“scale-independent” computing with Wallaroo](https://vimeo.com/234753585). The term “serverless” kept coming up in conversations, but the constraints of existing serverless frameworks limited the discussions.

First, a bit of context. Wallaroo is not based on abstract principles. Wallaroo is based on our team’s years of experience building and operating data applications. In my case, that includes applications in adtech, grid computing, and ultra low-latency algorithmic trading. In each case, going from a development version to a robust production version, and then adapting that production version as volumes grew, or something else changed, forced a lot of time to be spent on infrastructure-related issues. We were solving the same problems involving scale and resiliency over and over.

Wallaroo was born from our desire to solve these recurring problems for once. It’s a framework for building and operating data applications that provides an API for implementing business algorithms that operate on data, and an engine for running those algorithms in a distributed manner and managing in-memory state. We started calling our approach “scale-independent,” meaning that the framework would take care of all scaling related issues.  "Scale-independent" processing with Wallaroo means that our API doesn’t need - or even let - a developer specify the number of servers or processes that their application will run on. It also means that the engine takes care of all the “infrastructure plumbing” related to scaling and resiliency. This allows Wallaroo applications to [go from a single CPU prototype to a multi-server production environment without any code change](https://vimeo.com/234753585), and for live applications to grow and shrink capacity on-demand.

Wallaroo needs to run on servers and integrate with messaging, data stores, and databases. So while Wallaroo is scale-independent, your application can’t scale seamlessly if the other services it relies on don’t. Fortunately, scale-independence is a larger computing trend that includes cloud computing, cloud databases, messaging services, serverless frameworks, and more. Taken as a whole, it means it’s going to get increasingly easier to build and operate applications without worrying about infrastructure or scale, and that Wallaroo will play an increasingly important role in that ecosystem.

Wallaroo was built for applications that existing frameworks are not well suited for, and there are some fundamental differences.

Performance is one fundamental difference. We designed Wallaroo to be able to ingest an event, operate on the data, update application state, apply business logic and generate a result in as low as a few microseconds, vs. hundreds of milliseconds when compared to existing frameworks. Even if you don’t need the speed, Wallaroo will perform much better in high volume cases, especially if the application needs to maintain state.

Algorithmic longevity is another key difference. With existing serverless frameworks your code receives updated data, it responds to that update, and then ends within minutes. With Wallaroo, algorithms can operate continuously for as long as wanted – whether it is to respond to an unbounded stream of data or to perform long-running analysis on historical data.

Finally, Wallaroo doesn’t require you to run in a specific cloud environment. The application that you build with its API and run with the engine can be deployed in production to any Linux environment. If that happens to be an enterprise data-center and not a cloud, your applications can still autoscale when you add servers to an existing running Wallaroo cluster.

Where is this taking us? We want to continue “to make it as simple as possible for firms to build and operate data applications” by reaching more developers, making Wallaroo easier, and more powerful. Strategically, Wallaroo needs to be a part of the overall ecosystem used to build and run applications. That means integrating into cloud services like Kinesis at AWS, and commonly used analytics and machine learning libraries. It also means being part of the community and engaging in conversations with developers, data scientists, and architects like you.  We want to understand what “serverless” and data processing mean for you and your use cases. Achieving our mission will involve continuously iterating and improving based on that understanding.

If Wallaroo sounds interesting or you want to talk more about what I’ve discussed here, please reach out to us at [hello@WallarooLabs.com](mailto:hello@WallarooLabs.com).  We really want to hear about your projects, your ideas, and what excites you about where Wallaroo (and computing in general) is headed.
