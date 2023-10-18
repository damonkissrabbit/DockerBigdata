## Kafka

### kafka new features

#### preface

在之前版本中Zookeeper在Kafka中担任了重要的角色，承担了Controller选举，Broker注册，TopicPartition注册和Leader选举，Consumer/Producer元数据管理和负载均衡等等很多任务，使Kafka完全摆脱Zookeeper的依赖也不是异彩依稀就能完成的事情

#### 从单点Controller到Controller Quorum

现阶段的Controller本质上就是kafka集群中的一台Broker，通过ZK选举出来，负责根据ZK中的元数据维护所有Broker，Partition和Replica的状态，但是，一旦没有ZK的辅助，Controller就要接受ZK的元数据存储，并且单点Controller失败会对集群造成破坏性的影响，因此在将来的版本中，Controller会变成一个符合Quorum原则（过半原则）的Broker集合	![图片](https://mmbiz.qpic.cn/mmbiz_png/UdK9ByfMT2N5C1LKibY2J950q1z6TLiabO6ZUhBgyOXpcMn8PsribVpF6tCboOm92Cc338n6bnAmYpZaeI7sYiav3g/640?wx_fmt=png&tp=wxpic&wxfrom=5&wx_lazy=1&wx_co=1) 

也就是说在实际应用中要求Controller Quorum的节点数位奇数且大于等于3，最多可以容忍（n / 2 - 1）个节点失败。当然，只有一个节点能成为领导节点即Active Controller，领导选举就依赖于内置的Raft协议变种（又称为KRaft）实现

#### Quorum节点状态机

在KRaft协议下，Quorum中的一个节点可以处于一下4种状态之一。

- Candidate（候选者）-- 主动发起选举

- Leader（领导者） -- 在选举过程中获得多数票

- Follower（跟随者）-- 已经投片给Candidate，或者正在从Leader复制日志

- Observer（观察者）-- 没有投票权的Follower，与ZK的Observer含义相同

   ![图片](https://mmbiz.qpic.cn/mmbiz_png/UdK9ByfMT2N5C1LKibY2J950q1z6TLiabOoCm9XZdsDYYdGnwJI3gZZ5pc6oUVVFxCwoMspjfarfQlMFxAQTLYNA/640?wx_fmt=png&tp=wxpic&wxfrom=5&wx_lazy=1&wx_co=1) 

#### 消息定义

经典Raft协议只定义了两种RPC消息，即AppendEntries与RequestVote，并且是以推模式交互的。为了适应kafka环境，KRaft协议以拉模式交互，定义RPC消息有以下几种

- Vote：选举的选票信息，由Candidate发送
- BeginQuorumEpoch： 新Leader当选时候发送，告知其他节点当前的Leader信息
- EndQuorumEpoch：当前Leader退位时发送，触发重新选举，用于graceful shutdown
- Fetch：复制Leader日志，由Follower/Observe发送一一可见，经典的Raft协议中的AppendEntries消息时Leader将日志推给Follower，而KRaft协议中则是靠Fetch消息从Leader拉取日志。同时Fetch也可以作为Follower对Leader活性探测

### The overall structure of the kafka producer client


![图片](https://mmbiz.qpic.cn/mmbiz_png/UdK9ByfMT2M3QBcLamp7mDxTLBcYiaWibTbqMkfGpJ8kAEqEibf0XPVxJ9KlkGpvzmqePre4VIBcF9aiaiakwGic2zqw/640?wx_fmt=png&tp=wxpic&wxfrom=5&wx_lazy=1&wx_co=1) 

整个生产者客户端由两个线程协调运行，这两个线程分为主线程和Sender线程（发送线程）
在主线程中由KafkaProducer创建消息，然后通过可能的拦截器、序列化器和分区器的作用之后缓存到消息累加器（RecordAccumulator，也称为消息收集器）中，Sender线程负责从RecordAccumulator中获取消息并将其发送到Kafka中

***RecordAccumulator***
RecordAccumulator主要用来缓存消息以便Sender线程可以批量发送，进而减少网络传输的资源消耗以提升性能。主线程发送过来的消息都会被追加到RecordAccumulator的某个双端队列（Deque）中，在RecordAccumulator的内部会为每个分区都维护一个双端队列。
消息写入缓存时，追加到双端队列尾部；sender读取消息时，从双端队列的头部读取。
Sender从RecordAccumulator中获取缓存的消息之后，会进一步将原本<partition，Deque<ProducerBatch>>的保存形式转变成<Node, List<ProducerBatch>>的形式，其中Node表示kafka集群的broker节点。
KafkaProducer要将此消息追加到指定主题的某个分区所对应的leader副本之前，首先你需要知道主题的分区数量，然后经过计算得出（或者直接指定）目标分区，之后KafkaProducer需要知道目标分区的leader副本所在的broker节点的地址、端口等信息才能建立连接，最终才能将消息发送到kafka
这里需要一个转换，对于网络连接来说，生产者客户端是与具体的broker节点建立的连接，也就是向具体的broker节点发送消息，而并不关心消息属于哪一个分区

***InFlightRequests***
请求在从Sender线程发往kafka之前还会保存袋InFligntRequests中，InFligntRequests保存对象的具体形式为Map<NodeId, Deque>，它的主要作用是缓存了已经发出去但是还没有收到响应的请求（NodeId是一个String类型，表示节点的id编号）

***拦截器 Interceptor***
生产者拦截器既可以用来在消息发送前做一些准备工作，比如按照某个规则过滤不符合条件的消息，修改消息的内容等，也可以用来在发送回调逻辑前做一些定制化的需求，比如统计类工作。生产者拦截器的使用也很方便，主要是自定义实现org.apache.kafka.clients.producer.ProducerInterceptor接口。ProducerInterceptor接口中包含3个方法

```java
public ProducerRecord<K, V> onSend(ProducerRecord<K, V> record);
public void onAcknowledgement(RecordMetadata metadata, Exception exception);
public void close();
```

kafkaProducer在将消息序列化和计算分区之前会调用生产者拦截器的onSend()方法来对消息进行相应的定制化操作。一般来说最好不要修改消息ProucerRecord的topic，key和partition等信息
kafkaProducer会在消息被应答（Acknowledgement）之前或消息发送失败时调用生产者拦截器的 onAcknowledgement() 方法 ， 优先于用户设定的 Callback 之前执行。这个方法运行在 Producer 的I/O线程中，所以这个方法中实现的代码逻辑越简单越好，否则会影响消息的发送速度。
 close() 方法主要用于在关闭拦截器时执行一些资源的清理工作。

  ***序列化器***
生产者需要用序列化器（Serializer）把对象转换成字节数组才能通过网络发送给kafka，而在对侧，消费者需要用反序列化器（Deserializer）把从kafka中收到的字节数组转换成相应的对象
生产者使用的序列化器和消费者使用的反序列化器是需要一一对应的，如果生产者使员工了某种序列化器，比如StringSerializer，而消费组使员工了另一种序列化器，比如IntegerSerializer，那么是无法解析出想要的数据的
序列化器都需要实现org.apache.kafka.common.serialization.Serializer接口，此接口有3个方法

```
public void configure(Map<String, ?> configs, boolean isKey)
public byte[] serialize(String topic, T data)
public void close()
```

configure()方法用来配置当前类，serializer()方法用来执行序列化操作，而close()方法用来关闭当前的序列化器

***分区器***
消息经过序列化之后就需要确定它发往的分区，如果消息ProducerRecord中指定了partition字段，那么就不需要分区器的作用，因为partition代表的就是要发往的分区号。
如果消息ProducerRecord中没有指定partition字段，那么就需要依赖分区器，根据key这个字段来计算partition的值。分区器的作用就是为消息分配分区





