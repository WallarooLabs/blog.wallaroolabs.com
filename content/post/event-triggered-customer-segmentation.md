+++
title = "Event Triggered Customer Segmentation"
date = 2018-07-17T10:40:34+02:00
draft = false
author = "rblasucci"
description = "In which we quickly and easily create a full application to use Wallaroo to manage an ad campaign for a Marsupial Fan Club."
tags = [
    "Python",
    "State",
    "Wallaroo",
]
categories = [
    "Python-Api",
    "State",
    "Stream-Processing",
]
+++

Today I'm going to show you how fast and easy it can be to set up a simple application with Wallaroo to manage an ad campaign.

## Backstory
You’re a data engineer getting hounded by the marketing team at the fictional online Marsupial Fan Club to support an online ad campaign they have conjured up with a goal of converting an ad for a hoodie with an adorable marsupial on the front to purchases..  The Marsupial-Fan-Club has a single mission - market marsupial chatzky to the adoring fans.  The marketing channels are Instagram and Facebook -  dedicated to adorable pictures of marsupials of all flavors and kinds. You support the business through  running a modest storefront with assorted items for sale -- coffee cups, hoodies, and the like. For the Marsupial aficionados, you also have a special loyalty-members-only list where you send out additional coupons and special content. Today, you'd like to run a promotion for 10% off your newest hoodie. But there's a twist! If one of your known loyalty members clicks on your ad, you want to send them a coupon for an additional 10% off. With Wallaroo, this is super easy! Let's take an in-depth look at how to get there.

## Data structures
First, let's consider what our data looks like, so you'll know what pieces of information you'll need to consider.

### Loyalty list
Most importantly, we have our loyalty list. Today, we're sending in a text file populated with non-existing email accounts (to ensure we don't use someone's real address), with each line simulating a new entry. This could be easily be data that's read from another source, instead. We'll be tracking emails, Facebook username, Instagram username, and their gender. You might also track things like date of last fanclub purchase, geography, age demographics, # of insta followers (to understand their social influence/reach), etc.
```
kangak@fakeemail.com, kangakerfluffle, kangakerfluffle, F
wackywallaroo@fakeemail.com, , wackywallaroo, M
...
```
This will easily convert into a python object, like so: 
```
class Customer(object):
    def __init__(self, customer_email, fb_user, insta_user, gender):
        self.customer_email = customer_email
        self.fb_user = fb_user
        self.insta_user = insta_user
        self.gender = gender
```
It's also a good idea to add a `LoyaltyCustomers` object containing a dictionary of all of the `Customer`s. This way we can search through the list for a specific loyalty member. This should also have an `add` function to add a new loyalty customer, to populate that list! 
```
class LoyaltyCustomers(object):
    def __init__(self):
        self.customers = {}
        
    def add(self, customer_email, loyaltycustomer):
        self.customers[customer_email]=loyaltycustomer
```

### Conversions
Next, you'll want to consider tracking a few conversions, so that you're able to determine what best reaches and resonates with your members. 

- **Click conversions** -- Who clicked an ad, and where it was clicked. 
- **Basket conversions** -- Who has placed an item into their shopping basket. 
- **Purchase conversions** -- Who has purchased a full shopping cart, and the total cost of that cart. 

Today, we'll be using text files for the conversions information but, again, it could easily be another source of information. First, the `ClickConversion` file. This sends along the name of the promotion, "MarsupialHoodie", that it's a `ClickConversion`, the email of the customer who clicked the ad, and where the ad was clicked (in this case, Instagram or Facebook).

```
MarsupialHoodie, ClickConversion, playfulwally@fakeemail.com, Instagram
MarsupialHoodie, ClickConversion, iamkevinkoala@fakeemail.com, Facebook
...
```

The `BasketConversion` case is similar. Again, the data contains the name of the promotion, the type of conversion, and the email. This time it also captures a list of items that have been added to the shopping cart, by `ItemID`. 

```
MarsupialHoodie, BasketConversion, kangak@fakeemail.com, [6;14]
MarsupialHoodie, BasketConversion, wildwombatzoo@fakeemail.com, [6]
...
```

Now, let's look at the `PurchaseConversion` data. It is close to the other two: name, conversion type, and email start the list. There is also a full list of items purchased and, finally, the total purchase cost. 

```
MarsupialHoodie, PurchaseConversion, wombatz@fakeemail.com, [6;9], 18.64
MarsupialHoodie, PurchaseConversion, wally@veryrealemail.com, [6], 9.45
...
```

Finally, you'll need a basic object to track each specific conversion, like so: 
```
class ClickConversion(object):
    def __init__(self, promo_ad, conversion, customer_email, where):
        self.promo_ad = promo_ad
        self.conversion = conversion
        self.customer_email = customer_email
        self.where = where

class BasketConversion(object):
    def __init__(self, promo_ad, conversion, customer_email, items):
        self.promo_ad = promo_ad
        self.conversion = conversion
        self.customer_email = customer_email
        self.items = items

class PurchaseConversion(object):
    def __init__(self, promo_ad, conversion,
    		       customer_email, items, total_cost):
        self.promo_ad = promo_ad
        self.conversion = conversion
        self.customer_email = customer_email
        self.items = items
        self.total_cost = total_cost
```
And that's it! Let's get ready to work with our data now!

## Application setup and pipelines
If you've used Wallaroo before, you'll be aware that the `application_setup` function is the central point of your application. Here you'll set up the fundamentals and create your pipelines. You'll need to ensure your app knows the data inputs and outputs. For the promotion today, you'll need two inputs: one for the loyalty list, and one for your conversions. You'll also need to set up your partitions for any partitioned state you'll need. 
```
def application_setup(args):
    input_addrs = wallaroo.tcp_parse_input_addrs(args)
    
    ll_host, ll_port = input_addrs[0]
    cc_host, cc_port = input_addrs[1]

    in_host, in_port = wallaroo.tcp_parse_input_addrs(args)[0]
    out_host, out_port = wallaroo.tcp_parse_output_addrs(args)[0]

    initial_partitions = range(0,10)
```
Next, you'll create your pipelines! You'll start by creating an `ApplicationBuilder` named "Ad Tech Application". This will contain your pipelines. 
```
ab = wallaroo.ApplicationBuilder("Ad Tech Application")
```
To manage today's ad campaign, you'll need only two pipelines. One to manage the loyal members list, holding it in state, and adding members as needed, and another to process the conversions as they come in. Let’s look at each individually. 

### Loyalty customers pipeline
Let’s start with the loyalty customers pipeline. Here, you’ll be processing a list of incoming loyalty customers, and saving them to state, so that you can access them later, as shown in the figure below.

![ll_decoder to save_customer](/images/post/event-triggered-customer-segmentation/ll_pipeline.png "Loyalty customers pipeline")

So let’s set up a pipeline to do this! You'll need to name the pipeline, here `"Load loyalty customers"`, then let Wallaroo know where to find, and how to decode, the incoming data using the `wallaroo.TCPSourceConfig` function.

```
ab.new_pipeline("Load loyalty customers",
    wallaroo.TCPSourceConfig(ll_host, ll_port, ll_decoder))
```
You've already seen the `ll_host` and `ll_port` variables, as they were set at the beginning of the function. Let's look more closely at `ll_decode`. This is where you'll convert the incoming information into a `Customer` object, for use in the application later. All decoders must be wrapped with a `@wallaroo.decoder` decorator, specifying the header length and the length format. Once that is declared, the remaining function is simply a matter of splitting the incoming data and mapping it into the `Customer` object.
```
@wallaroo.decoder(header_length=4, length_fmt=">I")
def ll_decoder(data):
    info = data.split(",")
    return Customer(info[0].strip(), info[1].strip(),
		    info[2].strip(), info[3].strip())
```

Next, you'll save the incoming customers to the `LoyaltyCustomers` object that you created before, so that they're available for use in later steps. There's a fair amount to unpack in this next step, so let's look at it piece by piece. You're using the `to_state_partition` method. This means that you'll be calling a function that requires working with state, and that state will be partitioned. `save_customer` is the function you're calling. `LoyaltyCustomers` is the state object you'll be accessing. `"loyalty customers"` is the name of the state. The state object name functions as the object’s unique key, so using this same name will ensure that the same state object is being accessed and used in different computations. `extract_conversion_key` is the method to get the partition keys. And finally, `initial_partitions` is the list of the initial state partitions you'll be using. 
```
ab.to_state_partition(save_customer, LoyaltyCustomers,
    "loyalty customers", extract_conversion_key, initial_partitions)
```
The `LoyaltyCustomers` object and `initial_partitions` have been already set up. Let's look at the `save_customer` function. Since this is a state computation function, it must be wrapped in the `@wallaroo.state_computation` decorator, and given a name. As part of the pipeline, this function takes in the information, `data` that was returned by the previous step. In this case, that is a fully formed `LoyaltyCustomer` object. It also takes in the state object that is being referenced, `loyalty_customers`. You then add the loyalty member information into the loyalty members list, and return. Here, you want to return `None`, because you're not passing any information any further along, and `True`. You need to return the tuple so that Wallaroo knows whether or not to save the current state of the data. Since it was updated, and it makes sense to save here, you'll return `True`. 
```
@wallaroo.state_computation(name="save customers")
def save_customer(data, loyalty_customers):
    loyalty_customers.add(data.customer_email, data)
    return (None, True)
```
Now, the `extract_conversion_key` method is where you'll define your partition keys. For your ad campaign today, it makes sense to hash the `customer_emails`, then take that number, modulo 10. If you used modulo 100, for example, you would be able to create 100 partitions. This is a convenient way to divide things into 10 partitions. The partition key function needs to be wrapped in a `@wallaroo.partition` decorator to be identified correctly. 
```
@wallaroo.partition
def extract_conversion_key(data):
    return hash(data.customer_email) % 10
```

Finally, since you returned `None` from your last step, and you aren't sending on any data, you'll call `ab.done()` to indicate the end of this pipeline. That's it! In just a very few lines of code, you've created your first pipeline and saved some important information to state.

### Conversions pipeline
Let's move on to your second, and final, pipeline. This one manages the flow of your conversions data. Here, your source is all of your conversion information. Your decoder needs to understand how to process each one individually, as they are likely to be different. Then, the conversions are processed. Here’s where you write the logic to determine whether to send that additional coupon code! Finally, you send that determination on to your sink, so that the email can be sent.

![cc_decoder to conversions to process_email_add_customer to sink](/images/post/event-triggered-customer-segmentation/cc_pipeline.png "Conversions pipeline")

Let's create this pipeline. 

```    
ab.new_pipeline("Conversions",
    wallaroo.TCPSourceConfig(cc_host, cc_port, cc_decoder))
```
Let's call the pipeline `"Conversions"`. You'll also need a new decoding function, and this time, it will be a more drawn-out process, as you'll need to manage all three types of conversions. The process is very similar, however. You'll split the data as it comes in, determine which type of conversion it is, and call the appropriate function. The decoder returns an object containing the decoded information. 
```
@wallaroo.decoder(header_length=4, length_fmt=">I")
def cc_decoder(data):
    info = data.split(",")
    if info[1].strip() == 'ClickConversion':
        conversion = build_click_conversion(info)
    elif info[1].strip() == 'BasketConversion':
        conversion = build_basket_conversion(info)
    elif info[1].strip() == 'PurchaseConversion':
        conversion = build_purchase_conversion(info)
    return conversion
```
Then the individual functions handle separating the data into the specific conversion types for later use. 
```
def build_click_conversion(info):
    return ClickConversion(info[0].strip(), info[1].strip(),
			   info[2].strip(), info[3].strip())

def build_basket_conversion(info):
    return BasketConversion(info[0].strip(), info[1].strip(),
    	   		    info[2].strip(), info[3].strip())

def build_purchase_conversion(info):
    return PurchaseConversion(info[0].strip(), info[1].strip(),
    	   		      info[2].strip(), info[3].strip(),
			      info[3].strip())
```
The next step in the pipeline will process your conversions data.  
```
ab.to_state_partition(process_email_add_customer, LoyaltyCustomers,
    "loyalty customers", extract_conversion_key, initial_partitions)
```
Similarly to your first pipeline, you'll call the `process_email_add_customer` function using the `LoyaltyCustomers` state object, using the same conversion keys and initial partitions as last time. The `process_email_add_customer` function actually handles two things: determining whether to send the extra 10% off to your loyalty customers when they've clicked your ad, and adding a new customer as a loyalty customer once they've completed a purchase. You'll need to send on both the full conversion information, as well as the `should_email` information to your next processor, for the email to be sent. So you'll need to return a tuple within a tuple. 
```
@wallaroo.state_computation(name="add_new_loyalty_customer")
def process_email_add_customer(conversion, loyalty_customers):
    should_email = False
    if conversion.customer_email in loyalty_customers.customers:
        if conversion.conversion == 'ClickConversion':
            should_email = True
    else:
        if conversion.conversion == 'PurchaseConversion':
            loyalty_customers.add(conversion.customer_email,
	        Customer(conversion.customer_email, '','',''))
    return ((conversion, should_email), True)
```
This time, rather than calling `ab.done()`, you'll want to send the data on to a sink. Wallaroo needs to know how to reach it. You'll also need to create a new encoder function.
```
ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, cc_encoder))
```
Your encoder message can be quite simple. Here, you'll quickly unpack the tuple that was sent from the previous pipeline step, and format that into a string. You might also want to send a message out to, for example, Kafka, for further processing. This function ensures that the message is formatted correctly for your next step. 
```
@wallaroo.encoder
def cc_encoder(data):
    (conversion, should_email) = data
    return ("Send additional promo code to: " + conversion.customer_email
            + ", " + str(should_email) + "\n")
```
This is the last step in the conversions pipeline. So, let's return the `ApplicationBuilder`, and you're done! 
```
return ab.build()
```
## Conclusions
In just over 120 lines of code, you've quickly and smoothly created a lightweight stream-processed application to manage an aspect of your ad campaigns. We'll be looking at more examples in future blog posts of small, quick applications that you can add on to your current setup. At Wallaroo, we're just excited to help you be more effective! 