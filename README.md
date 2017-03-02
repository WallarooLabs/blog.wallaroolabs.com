This is the source for the engineering.sendence.com blog.

The blog is built using the [hugo static website engine](gohugo.io). It's hosted on GitHub pages and built and deployed using TravisCI.

## Installing Hugo

If you are writing a blog post, you'll need a recent version of Hugo. On OSX, you can install by doing:

```bash
brew update && brew install hugo
```

Otherwise you can download the hugo binary [from their website](gohugo.io).

## Setting up your author info

The first time you go to write a blog post, you should first set up your author info and commit and push that. You only need to do this one time.

In the `data/author` folder, create a new json file with your author info. The name of the file should match the author name you will use in your blog post front matter.

For example, in my posts, I put `author = "seantallen"` so my author file is called `seantallen.json`

Your json file needs to contain 3 pieces of information, your name as it will be displayed on the website, your short bio (can include markdown formatting), and the name of your avatar image. 

When setting up your author info, be sure to include your avatar file in `static/images/author`.

## Creating a blog post

First things first, its good to know the name of your post or at least a 
working title. This title will be used when picking a name for the post's file.
Create a feature branch for your post, I suggest using your post name as the branch name so, if your title was "Hello Wallaroo" then your branch would be called "hello-wallaroo". Once you are working on a new branch, you will need hugo to create your post file with our standard Sendence front-matter. If your title is "Hello Wallaroo" then you would create the post by running:

```bash
hugo new post/hello-wallaroo.md
```

This will create a new blog post with our standard front-matter in the `content/post` directory. If your post needs images, downloads etc, you should create a directory in `static/images` such as `static/images/hello-wallaroo`. This can then be referenced from your post markdown as `/images/hello-wallaroo`. Yes, all these things might not technically be images but, don't worry about it.

## Standard Sendence post front-matter

When you create a blog post using the above instructions, standard Sendence front-matter will be automatically populated with some default values:

```toml
+++
title = "example"
slug = "post-url-name"
draft = true
date = "2017-03-02T15:20:13-05:00"
categories = ["category 1","category 2"]
tags = ["tag 1","tag 2"]
description = "Lorem ipsum dolor sit amet, consectetur adipisicing elit. Earum similique, ipsum officia amet blanditiis provident ratione nihil ipsam dolorem repellat."
author = "Author Name"
+++
```

Let's quickly run through each.

* Title is the title of your post
* Slug is used in the url. Once the post is published, this should never change. If you post is called "Hello Wallaroo" then the slug should be "hello-wallaroo"
* Draft should be switched from `true` to `false` when you want the post published on the website.
* Date at the time you change the value of `draft` to `true`, you should date to the current date and time.
* Categories are used to group a series of posts together. For example, our series of posts introducing the world to Wallaroo is under the category "Hello Wallaroo". Categories should be used for a related series of posts that you would expect benefit from being read in order. You can [check the website](http://engineering.sendence.com/categories/) to see existing categories.
* Tags are a free form way of orthogonally organizing posts. Example tags include "performance", "scaling", "wallaroo", "exactly-once" etc. Use whatever tags seem appropriate on your post. Before creating a new tag, [check the website](http://engineering.sendence.com/tags/) to see if there is already an existing appropriate tag.
* Description is a short description of your post. It is optional. If it exists, it will be used on the main index page as the summary of the post and in page metadata where it will be picked up by search engines, twitter and such.
* Author is your author name. Make sure this is correct as it will be used to automatically populate your author info on the blog post. See the earlier "Setting up your author info" section of this document for more information

## Viewing your post

```bash
hugo server --buildDrafts
```

will render the website (including drafts) and start up a server. You can view the server running locally on [localhost:1313](http://localhost:1313).

## Publishing your post

When the time has come to publish your post, update the front-matter so that...

* `date` is set to the current date and time
* `draft` is set to `false`

Then open a PR against this repo. Travis CI will verify that the post builds correctly. Once you know everything is building, find someone who will do a final review of your post and assign them as a reviewer.

The final reviewer should check out your PR branch and verify that the post builds and that everything looks good, there are no broken images etc. Once they have verified everything is good they should

* `Rebase and merge` the post using the GitHub UI
* Delete the branch for the post using the GitHub UI

## More...

If you need to learn more, talk to someone on the team, read the hugo documentaiton and check out the output from its help command.
