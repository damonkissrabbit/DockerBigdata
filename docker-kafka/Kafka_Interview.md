***segment***

kafka把partition分成若干的segment，segment是kafka的最小存储单元，在broker往分区里面写入数据时候，如果达到segment上限，就关闭当前segment并打开一个新segment。没有关闭的segment叫做活跃片段，活跃片段永远不会被删除。（默认segment上限是1GB大小或存活一周，所以如果配置了topic数据保存1天，但是5天了segment都没有1GB，则数据会存储5天）。这样设计相当于把整个partition这个大文件拆成了细碎的小文件，避免了在一个大文件里面查找内容，如果要数据过期要删除的话可以直接删除整个文件，比删文件里面的内容更简单。

![1695084061150](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084061150.png)

***存储与查询***

segment的真正存储会分成2份文件，一种是.index的索引文件，一种是.log的数据存储文件，成对出现。index保存offset的索引，log保存真正的数据内容。index文件的文件名是本文件的起始offset。

![1695084091077](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084091077.png)

***索引建立***

kafka建立的这种索引也就是稀疏索引，即建立较少offset的索引用来较少内存使用。但是由于offset的索引建立得不完全，即查询命中也能消耗更多时间。

***kafka用途有哪些？使用场景如何？***

- 消息系统：kafka和传统的消息系统（也称为消息中间件）都具备系统解耦、冗余存储，流量削峰、缓冲、异步通信、可恢复性等功能。与此同时，kafka还提供了大多数消息系统难以实现的消息顺序性保障及回溯消费的功能。
- 存储系统：kafka吧消息持久化到磁盘，相当于其他基于内存存储的系统而言，有效地降低了数据丢失的风险，也正是得益于kafka的消息持久化功能和多副本机制，我们可以把kafka作为长期的数据存储系统来使用，只需要把对应的数据保留策略设置为永久或启用主题的日志压缩功能即可
- 流式处理平台：kafka不仅为每个流行的流式处理框架提供了可靠的数据来源，还提供了一个完整的流式处理类库，比如窗口、连接、变换和聚合等各类操作

***kafka中的ISR、AR代表什么、IST伸缩指什么***

分区中的所有副本统称为AR（Assigned Replicas）。所有与leader副本保持一定程度同步的副本（包括leader副本在内）组成ISR（In-Sync Replicas），ISR集合是AR集合中的一个子集。

***ISR的伸缩***

leader副本负责维护和跟踪ISR集合中所有follower副本的滞后状态，当follower副本落后太多或失效时，leader副本会把它从ISR中剔除出去，如果OSR集合中有leader副本追上leader副本，那么leader副本会把它从OSR集合转移至ISR集合，默认情况下，当leader副本发生故障时，只有ISR集合中的副本才有资格被选举为新的leader，而在OSR集合中的副本则没有任何机会（不过这个原则也可以通过修改相应的参数配置来改变）

[replica.lag.max.ms](http://replica.lag.max.ms)：这个参数的含义是Follower副本能够落后Leader副本的最长时间间隔，当前默认值是10秒

unclean.leader.election.enable：是否允许unclean领导者选举。开启unclean领导者选举可能会造成数据丢失，但好处是，它使得分区Leader副本一直存在，不至于对外提供服务，因此提升了高可用性

***kafka中的HW、LEO、LSO、LW等分别代表了什么***

HW是High watermark的缩写，俗称高水位，它标识了一个特定的消息偏移量（offset），消费者只能拉取到这个offset之前的消息

LSO是LogStartOffset，一般情况下，日志文件的其实偏移量logstartoffset等于第一个日志分段的baseoffset，但这并不是绝对地，logstartoffset的值可以通过deleteRecordsRequest请求（比如使用kafkaAdminClient的deleteRecords()方法）、使用功能kafka-delete-records.sh脚本、日志的清理和截断等操作进行修改

![1695084114679](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084114679.png)

如上图所示，它代表一个日志文件，这个日志文件中有9条信息，第一条消息的offset（LogStartOffset）为0，最后一条消息的offset为8，offset为9的消息用虚线框表示，代表下一条要写入的消息，日志文件的HW为6，表示消费者只能拉取到offset0至5之间的消息，而offset为6的消息对消费者而言是不可见的。

LEO是Log End Offset的缩写，它表识当前日志文件中下一条待写入消息的offset，上图中offset为9的位置即当前日志文件的LEO，LEO的大小相当于当前日志分区中最后一条消息的offset值加1，分区ISR集合中的每个副本都会维护自身的LEO，而ISR集合中的最小的LEO即为分区的HW，对消费者而言只能消费HW之前的消息

LW是Low watermark的缩写，俗称低水位，代表AR集合中最小的logstartoffset值，副本的拉取请求（fetcheRequest，它有可能触发新建日志分段而旧的被清理，进而导致logstartoffset的增加）和消息删除请求（deleteRecordRequet）都有可能促使LW的增长

***kafka中是怎么体现消息顺序性的***

可以通过分区策略体现消息顺序性

分区策略有轮询策略，随机策略，按消息键保序策略

按消息键保序策略：一旦消息被定义了key，那么你就可以保证同一个key的所有消息都进入到相同的分区里面，由于每个分区下的消息处理都是有顺序的，故这个策略被称为按消息键保序策略

```java
List<PartitionInfo> partitions = cluster.partitionsForTopic(topic);
return Math.abs(key.hashCode()) % partitions.size();
```

***kafka中的分区器，序列化器，拦截器是否了解，他们之间的处理顺序是什么***

- 序列化器：生产者需要用序列化器（Serializer）把对象转换成字节数组才能通过网络发送给kafka，而在对侧，消费者需要使用反序列化器（Deserializer）把从kafka中收到的字节数珠转换成相应的对象
- 分区器：分区器的作用就是为消息分配分区，如果消息ProducerRecord中没有指定partition字段，那么就需要依赖分区器，根据key这个字段来计算partition的值
- kafka一共有两种拦截器：生产者拦截器和消费者拦截器 
  - 生产者拦截器即可以用来在消息发送前做一些准备工作，比如按照某个规则过滤不符合要求的消息、修改消息的内容等，也可以用来在发送回调逻辑前做一些定制化的需求，比如统计类工作
  - 消费者拦截器主要在消费到消息或在提交消费位移时进行一些定制化的操作

消息在通过send()方法发往broker的过程中，有可能需要经过拦截器（Interceptor）、序列化器（Serializer）和分区器（Partitioner）的一系列作用之后才能被真正的发往broker。拦截器一般不是必需的，而序列化器是必需的。消息经过序列化之后就需要确定它发往的分区，如果消息ProducerRecord中指定了partition字段，那么就不需要分区器的作用，因为partiton代表的就是要发往的分区号

处理顺序：拦截器 → 序列化器 → 分区器

kafkaProducer在将消息序列化和计算分区之前会调用生产者拦截器的onSend(）方法来对消息进行相应的定制化操作

然后生产者需要用序列化器（Serializer）把对象转换成字节数组才能通过网络发送给kafka。最后可能会被发往分区器为消息分配分区

***kafka生产者客户端的整体结构是什么样的***

![Untitled](https://prod-files-secure.s3.us-west-2.amazonaws.com/0e420b59-2a74-42c2-929e-a5414070f3e3/f002d9d3-4076-480c-8560-8fdf0f908d37/Untitled.png)

整个生产者客户端由两个线程协调运行，这两个线程分别为主线程和Sender线程（发送线程）。在主线程中由kafakProducer创建消息，然后通过可能的拦截器，序列化器和分区器的作用之后缓存到消息累加器（RecordAccumulator，也称为消息收集器）中。sender线程负责从RecordAccumulator中获取消息并将其发送到kafka中。RecordAccumulator中获取消息并将其发送到kafka中。RecordAccumulator主要用来缓存消息以便sender县城可以批量发送，进而减少网络传输的资源消耗以提升性能。

***kafka生产者客户端中使用了几个线程来处理，分别是什么***

整个生产者客户端由两个线程协调运行，这两个线程分别是主线程和sender线程（发送线程）。在主线程中由kafkaProucer创建消息，然后通过可能的拦截器、序列化器和分区器的作用之后缓存到消息累加器（RecordAccumulator，也称为消息收集器）中。

sender线程负责从RecordAccumulator中获取消息并将其发送到kafka中

***kafka的旧版scala消费者客户端的设计有什么缺陷***

老板的comsuner group把唯一保存在zookeeper中，apache zookeeper是一个分布式协调服务框架，kafka中毒依赖它实现各种各样的协调管理。把位移保存在zookeeper外部系统的做法，最显而易见的好处是减少了kafka broker端的状态保存开销

zookeeper这类框架并不适合进行频繁的写更新，而consumer group的唯一更新确是一个非常频繁的操作，这种大吞吐量的写操作会极大的拖慢zookeeper集群的性能

***消费者组中的消费者个数如果超过topic的分区，那么就会有消费者消费不到数据，这句话是否正确，如果正确，有没有什么手段***

一般来说如果消费者过多，出现了消费者的个数大于分区个数的情况，就会有消费者分配不到任何分区

开发中可以继承AbstractPartitionAssignor实现自定义消费策略，从而实现同一消费组的任意消费组都可以消费订阅主题的所有分区

```java
public class BroadcastAssignor extends AbstractPartitionAssignor{
    @Override
    public String name() {
        return "broadcast";
    }

    private Map<String, List<String>> consumersPerTopic(
            Map<String, Subscription> consumerMetadata) {
        （具体实现请参考RandomAssignor中的consumersPerTopic()方法）
    }

    @Override
    public Map<String, List<TopicPartition>> assign(
            Map<String, Integer> partitionsPerTopic,
            Map<String, Subscription> subscriptions) {
        Map<String, List<String>> consumersPerTopic =
                consumersPerTopic(subscriptions);
        Map<String, List<TopicPartition>> assignment = new HashMap<>();
		   //Java8
        subscriptions.keySet().forEach(memberId ->
                assignment.put(memberId, new ArrayList<>()));
		   //针对每一个主题，为每一个订阅的消费者分配所有的分区
        consumersPerTopic.entrySet().forEach(topicEntry->{
            String topic = topicEntry.getKey();
            List<String> members = topicEntry.getValue();

            Integer numPartitionsForTopic = partitionsPerTopic.get(topic);
            if (numPartitionsForTopic == null || members.isEmpty())
                return;
            List<TopicPartition> partitions = AbstractPartitionAssignor
                    .partitions(topic, numPartitionsForTopic);
            if (!partitions.isEmpty()) {
                members.forEach(memberId ->
                        assignment.get(memberId).addAll(partitions));
            }
        });
        return assignment;
    }
}
```

注意组内广播的这种实现方式会有一个严重的问题：默认的消费唯一的提交会失效

***消费组提交消费位移时提交的是当前消费到的最新消息的offset还是offset+1***

在就消费组客户端中，消费位移时存储在zookeeper中的，而在新的消费组客户端中，消费位移存储在kafka内部的主题的 __consumer_offsets中

当前消费组需要提交的消费位移时offset+1

***有哪些情形会造成重复消费***

1. Rebalance

   一个consumer正在消费一个分区的一条信息，还没有消费完，发生了rebalance（又加入了一个consumer）从而导致这条消息没有消费成功，rebalance之后，另一个consumer又把这条消息消费一遍

2. 消费者端手动消费

   如果先消费消息，在更新offset位置，导致消费重复消费

3. 消费者端自动提交

   设置offset为自动提交，关闭kafka时，如果在close前，调用consumer.unsubscribe()，则有可能部分offset没提交，下次重启会重复消费

4. 生产者端

   生产者因为业务问题导致的宕机，在重启之后可能数据会重发

***哪些情景下会造成消息漏消费***

1. 自动提交

   设置offset为自动定时提交，当offset被自动定时提交时，数据还在内存那种未处理，此时刚好被线程kill掉，那么offset已经提交，但是数据未处理，导致这部分内存中的数据丢失

2. 生产者发送消息

   发送消息设置的是fire-and-forget（发完即忘），它只管往kafka中发送消息而并不关心消息是否正确到达。不过在某些时候（比如发生不可重试异常时）会造成消息的丢失。这种发送方式的性能最高，可靠性也最差

3. 消费者端

   先提交位移，但是消息还没消费完就宕机了，造成了消息没有被消费，自动位移提交同理

4. acks没有设置为all

   如果broker还没把消息同步到其他broker的时候宕机了，那么消息将丢失

***kafkaConsumer是非线程安全的，那么怎么样实现多线程消费***

1. 线程封闭，即为每个线程实例化一个kafkaConsumer对象

   ![1695084144812](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084144812.png)

   一个线程对应一个kafkaConsumer实例，我们可以称之为消费线程。一个消费线程可以消费一个或多个分区中的消息，所有的消费线程都隶属于同一个消费组

2. 消费组程序使用单或多线程获取消息，同时创建多个消费线程执行消息处理逻辑

   获取消息的线程可以是一个，也可以是多个，每个线程维护专属的kafkaConsumer实例，处理消息则交给特定的线程池来做，从而实现获取与消息处理的真正解耦

   ![1695084162600](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084162600.png)

![1695084182354](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084182354.png)

***消费者和消费组之间的关系***

- consumer group下可以有一个或多个consumer实例，这里的实例可以是一个单独的进程，也可以是同一进程下的线程，在实际场景中，使用进程更为常见一些
- group id是一个字符串，在一个kafka集群中，它表示惟一的一个consumer group
- consumer group下所有实例订阅的主题的单个分区，只能分配给组内的某个consumer实例消费。这个分区当然也可以被其他的group消费

***使用kafka-topics.sh创建一个topic之后，kafka背后执行了什么逻辑***

当执行完脚本之后，kafka会在log.dir或log.dirs参数所配置的目录下创建相应的主题分区，默认情况下这个目录为/tmp/kafka-logs/

在zookeeper的/brokers/topics/目录下创建一个同名的实节点，该节点中记录了该主题的分区副本分配方案

```java
[zk: localhost:2181/kafka(CONNECTED) 2] get /brokers/topics/topic-create
{"version":1,"partitions":{"2":[1,2],"1":[0,1],"3":[2,1],"0":[2,0]}}
```

***topic的分区数可以不可增加，如果可以怎么增加，如果不可以，是为什么***

可以增加，使用kafka-topics脚本，结合 —alter 参数来增加某个主题的分区数，命令如下

```java
kafka-topics.sh --bootstrap-server broker_host:port --alter 
	--topic <topic_name> --partitions <new_partition_numbers>
```

当分区数增加时，就会触发订阅该主题的所有Group开启rebalance

首先，rebalance过程对consumer group消费过程由极大的影响。在rebalance过程中，所有consumer实例都会停止消费，等待rebalance完成，这是rebalance为人诟病的一个方面

其次，目前Rebalance的时机是所有consumer实例共同参与，全部重新分配所有分区，其实更高效的做法是尽量减少分配方案的变动

Rebalance太慢了

***Rebalance机制***

Rebalance就是说如果消费组里的消费组数量有变化或消费的分区数有变化，kafka会重新分配消费者消费分区的关系，如果consumer group中某个消费者挂了，此时会自动把分配给他的分区交给其他的消费组，如果他又重启了，那么又会把一些分区重新叫还给他

Rebalance只针对subscribe这种不指定分区消费的情况，如果通过assign这种消费方式指定了分区，kafka不会进行Rebalance

以下情况会触发Rebalance

- 消费组里的consumer增加或减少了
- 动态给topic增加了分区
- 消费组订阅了更多的topic

Rebalance过程中，消费者无法从kafka消费消息，这对kafka的TPS会有影响，如果kafka集群内节点较多，比如数百个，那重平衡可能会耗时较多，所以应尽量避免在系统高峰期的重平衡操作

1. 消费者Rebalance分区分配策略

   range()、rount-robin(轮询)、sticky(粘性)

   kafka提供了消费者客户端参数partition.assignment.strategy来设置消费者与订阅主题之间的分区分配策略。默认情况为range分配策略

   ![1695084248341](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084248341.png)

2. Rebalance过程

   当有消费者加入消费组时候，消费者、消费组及组协调器之间会经历一下几个阶段

   ![1695084262780](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084262780.png)

   ***第一阶段：选择组协调器***

   组协调器GroupCoordinator：每个consumer group都会选择一个broker作为自己的组协调器coordinator，负责监控这个消费组里的所有消费者的心跳，以及判断是否宕机，然后开启消费者Rebalance

   consumer group中的每个consumer启动时会向kafka集群中的某个节点发送FindCoordinatorRequest请求来查找对应的组协调器GroupCoordinator，并跟其建立网络连接

   组协调器的选择方式：consumer消费的offset要提交到__consumer_offset的哪个分区，这个分区leader对应的broker就是这个consumer group的coordinator

   ***第二阶段：加入消费组JOIN GROUP***

   在成功找到消费组所对应的GroupCoordinator之后就进入了消费组的阶段，在此阶段的消费组会向GroupCoordinator发送JoinGroupRequest请求，并处理响应。然后GroupCoordinator从一个consumer group中选择第一个加入group的consumer作为leader（消费组协调器），把consumer grou情况发送给这个leader，接着这个leader会负责指定分区方案

   ***第三阶段（sync group）***

   consumer leader通过给GroupCoordinator发送SyncGroupRequest，接着GroupCoordinator就把分区方案下发给各个consumer，他们会根据指定分区的leader broker进行网络连接以及消息消费

   ![1695084282617](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084282617.png)

***topic的分区数可不可以减少？如果可以怎么减少？如果不可以，又是为什么？***

不支持，因为删除的分区中的消息不好处理，如果直接存储到现有分区的尾部，消息的时间戳就不会递增，如此对于spark，flink这类需要消息的时间戳（事件时间）的组件将会收到影响；如果分散插入到现有的分区，那么在消息量很大的时候，内部的数据复制会占用很大的资源，而且在复制期间，此主题的可用性又如何得到保障？与此同时，顺序性问题，事务性问题，以及分区和副本的状态机切换问题都是不得不面对的。

***创建topic时如何选择合适的分区数***

在kafka中，性能与分区数有着必然的关系，在设定分区数时一般也需要考虑性能的因素。对不同的硬件而言，其对应的性能也会不太一样。

可以使用kafka本身提供的用于生产者性能测试的kafka-producer-perf-test.sh和用于消费者性能测试的kafka-consumer-perf-test.sh来进行测试

增加合适的分区数可以在一定程度上提升整体的吞吐量，但超过对应的阈值之后吞吐量不升反将。如果应用对吞吐量有一定程度上的要求，则建议在投入生产环境之前对同款硬件资源做一个完备的吞吐量相关的测试，以找到合适的分区数阈值区间

分区数的多少还会影响系统的可用性。如果分区数非常多，如果集群中的某个broker节点宕机，那么就会有大量的分区需要同时进行leader角色切换，这个切换的过程会耗费一笔可观的时间，并且在这个时间窗口内这些分区也会变得不可用

分区数越多也会让kafka的正常启动和关闭的耗时变得越长，与此同时，主题的分区数越多不仅会增加日志清理的耗时，而且在被删除时也会耗费更多的时间。

***kafka有哪些内部topic，他们都有什么特征？各自作用是什么***

__consumer_offsets: 作用是保存kafka消费者的位移信息

__transaction_state: 用来存储事务日志信息

***优先副本是什么？它有什么特殊的作用***

所谓的优先副本就是指AR集合列表中的第一个副本。

理想情况下，优先副本就是该分区的leader副本，所以也可以称为 preferred leader。kafka要确保所有主题的优先副本在kafka集群中均匀分布，这样就保证了所有分区的leader均衡分布。以此来促进集群的负载均衡，这一行为也称为 分区平衡

***kafka有哪基础地方有分区分配的概念，简述大致的过程及原理***

1. 生产者的分区分配是指每条消息指定其所要发往的分区，可以编写一个具体的类实现org.apache.kafka.clients.producer.Partitioner接口
2. 消费者中的分区分配是指消费者指定其可消费消息的分区。kafka提供了消费者客户端参数partition.assignment.strategy来设置消费者与订阅主题之间的分区分配策略
3. 分区副本的分配是指为集群指定创建主题时的分区副本分配方案，即在哪个broker中创建哪些分区的副本。kafka-topics.sh脚本中提供了一个replica-assignment参数来手动指定分区副本的分配方案

***kafka的日志目录结构***

![1695084314764](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084314764.png)

kafka中的消息时以主题为基本单位进行归类的，各个主题在逻辑上相互独立。每个主题有可以分为一个或多个分区，不考虑多副本的情况，一个分区对应一个日志（log），为了防止log过大，kafka又引入了日志分段（LogSegment）的概念，将Log切分为多个LogSegment，相当于一个巨型文件被平均分配为多个相对较小的文件。

Log和LogSegment也不是纯粹物理意义上的概念，Log在物理上只以文件夹的形式存储，而每个LogSegment对应于磁盘上一个日志文件和两个索引文件，以及可能的其他文件（比如以 .txnindex 为后缀的事务索引文件）

***kafka中有哪些索引文件***

每个日志分段文件对应了两个索引文件（LogSegment），主要用来提高查找信息的效率。

偏移量索引文件（.index）用来建立消息偏移量（offset）到物理地址之间的映射关系，方便快速定位消息所在的物理文件位置。

时间戳索引文件（.timeindex）则根据指定的时间戳（timestamp）来查找对应的偏移量信息

***指定了一个timestamp，kafka怎么查找到对应的消息***

kafka提供了一个offsetsForTimes() 方法，通过timestamp来查询与此对应的分区位置。offsetsForTimes()方法的参数timestampsToSearch是一个Map类型，key为待查询的分区，而value是待查询的时间戳，该方法会返回时间戳大于等于待查询时间的第一条消息对应的位置和时间戳，对应于offsetAndTimestamp中的offset和timestamp字段

***对kafka的Log Retention的理解***

日志删除（Log Retention）：按照一定的保留策略直接删除不符合条件的日志分段。我们可以通过broker端参数log.cleanup.policy来设置日志清除策略，此参数的默认值为delete，即采用日志删除的清理策略

1. 基于时间

   日志删除会检查当前日志文件中是否保留时间超过设定的阈值（retentionMs）来寻找可删除的日志分段的文件集合（deleteableSegmetns）retentionMs可以通过broker端参数log.retention.hours、log.retention.minutes和log.retention.ms来配置，默认情况下只配置了 log.retention.hours 参数，其值为168，故默认情况下日志分段文件的保留时间为7天。

   删除日志片段时，首先会从Log对象中维护日志分段的跳跃表中移除待删除的日志分段，以保证没有线程对这些日志分段进行读取操作。然后将日志分段所对应的所有文件添加上 .deleted 的后缀（当然也包括所对应的索引文件）。最后交由一个以 delete-file 命名的延迟任务来删除这些以 .deleted 为后缀的文件，这个任务的延迟执行时间可以通过 [file.delete.delay.ms](http://file.delete.delay.ms) 参数来调节，此参数的默认值为60000，即1分钟

2. 基于日志大小

   日志删除任务会检查当前日志的大小是否超过设定的阈值（retentionSize）来寻找可删除的日志分段的文件集合（deletableSegments）

   retentionSize可以通过broker端参数log.retention.bytes来配置，默认值为-1，表示无穷大，注意log.retention.bytes配置的是Log中所有日志文件的总大小，而不是单个日志分段（确切地说应该为.log日志文件）的大小。单个日志分段的大小由broker端参数log.segment.bytes来限制，默认1GB。这个删除操作和基于时间的保留策略的删除操作相同

3. 基于日志起始偏移量

   基于日志其实偏移量的保留策略的判断依据是某日志分段的一下个日志分段的起始偏移量baseOffset是否小于等于logStartOffset，若是，则可以删除此日志分段

   ![1695084334174](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084334174.png)

   如上图所示，假设 logStartOffset 等于25，日志分段1的起始偏移量为0，日志分段2的起始偏移量为11，日志分段3的起始偏移量为23，通过如下动作收集可删除的日志分段的文件集合 deletableSegments：

   从头开始遍历每个日志分段，日志分段1的下一个日志分段的起始偏移量为11，小于 logStartOffset 的大小，将日志分段1加入 deletableSegments。 日志分段2的下一个日志偏移量的起始偏移量为23，也小于 logStartOffset 的大小，将日志分段2加入 deletableSegments。 日志分段3的下一个日志偏移量在 logStartOffset 的右侧，故从日志分段3开始的所有日志分段都不会加入 deletableSegments。 收集完可删除的日志分段的文件集合之后的删除操作同基于日志大小的保留策略和基于时间的保留策略相同

***kafka的Log Compaction***

日志压缩（Log Compaction）：针对每个消息的key进行整合，对于有相同key的不同value值，只保留最后一个版本

如果要采用日志压缩的清理策略，就需要将log.cleanup.policy设置为compact，并且还需要将log.cleaner.enabl设定为true

![1695084349066](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084349066.png)

Log Compaction对于有相同key的不同value值，只保留最后一个版本，如果应用只关心key对应的最新value值，则可以开启kafka的日志清理功能，kafka会定期将相同key的消息进行合并，只保留最近的value值

***kafka底层存储***

***页缓存***

页缓存是操作系统实现的一种主要的磁盘缓存，以此用来减少对磁盘IO的操作，具体来说，就是把磁盘中的数据缓存到内存中，把对磁盘的访问变为对内存的访问。

当一个进程准备读取磁盘上的文件内容时，操作系统会查看待读取的数据所在的页（page）是否在页缓存（pagecache）中，如果存在（命中）则直接返回数据，从而避免了对物理磁盘的IO操作，如果没有命中，则操作系统会向磁盘发起读取请求并将读取的数据存入页缓存，之后再将数据返回给进程。

同样，如果一个进程需要将数据写入磁盘，那么操作系统也会检查数据对应的页是否在页缓存中，如果不存在，则会先在页缓存中添加相应的页，最后将数据写入对应的页，被修改过的页也就变成了脏页，操作系统会在合适的时间把脏页中的数据写入磁盘，以保证数据的一致性。

用过java的人一般都知道：对象的内存开销非常大，通常是真实数据大小的几倍甚至更多，空间使用率低下；java垃圾回收会随着堆内数据的增多而变得越来越慢，基于这些因素，使用文件系统并依赖于页缓存的做法明显要优先卫华一个进程内缓存或其他结构，至少我们可以省去一份进程内部的缓存消耗，同事还可以通过结构紧凑的字节码来替代使用功能对象的方式以节省更多的空间

此外，即使kafka服务重启，页缓存还是会保持有效，然而进程内的缓存却需要重建，这样也极大地简化了代码逻辑，因为维护页缓存和文件之间的一致性交由操作系统来负责，这样会比进程内维护更加安全有效。

***零拷贝***

除了消息顺序追加、页缓存等技术，kafka还使用零拷贝（zero-copy）技术来进一步提升性能，所谓的零拷贝只是将数据直接从磁盘文件复制到网卡设备中，而不需要经由应用程序之手，零拷贝大大提高了应用程序的性能，减少了内核和用户模式之间的上下文切换，对linux操作系统而言，零拷贝技术依赖底层的sendfile()方法实现，而对于java而言，FileChannel.trasferTo()方法底层实现就是sendfile()方法

***kafka的延时操作的原理***

kafka中有多种延迟操作，比如延时生产，还有延时拉取（DelayedFetch）、延时数据删除（DelayedDeleteRecords）等

延时操作创建之后会被加入延时操作管理器（DelayedOperationPurgatory）来做专门的处理，延时操作有可能会超时，每个延时操作管理器都会配备一个定时器（SystemTimer）来做超时管理，定时器的底层就是采用时间轮（TimeWheel）实现的

***kafka控制器的作用***

在kafka集群中有一个或多个broker，其中有一个broker会被选举为控制器（kafka controller），它复杂管理整个集群中所有分区和副本的状态，当某个分区的leader副本出现故障时，由控制器复杂为该分区选举新的leader副本，当检查到某个分区的ISR集合发生变化时，有控制器复杂通知所有broker更新其元数据信息，当使用kafka-topics.sh脚本为某个topic增加分区数量时，同样还是由控制器复杂分区的重新分配

***kafka controller***

控制器组件（controller），是kafka的核心组件，它的主要作用是在zookeeper 的帮助下管理和协调整个kafka集群，集群中任意一条broker都能充当控制器的角色，但是在运行过程中，只能以一个broker成为控制器，行使管理和协调的职责

***什么是controller broker***

在分布式系统中，通常有一个协调者，该协调者会在分布式系统发生异常时发挥特殊的作用，在kafka中该控制器并没有什么特殊之处，它本身就是一个普通的broker，只不过需要负责一些额外的工作（追踪集群里面其他的broker，并在合适的时候处理新加入的和失败的broker节点，Rebalance分区，分配新的leader分区）

***controller broker是怎么被选举出来的***

在broker启动时，会尝试去zookeeper中创建/controller节点，kafka当前选举控制器的规则是：第一个成功创建/controller节点的broker会被指定为控制器

***controller broker具体作用***

controller broker的主要职责有很多，主要是一些管理行为

- 创建、删除主题，增加分区并分配leader分区
- 集群broker管理（新增broker，broker主动关闭，broker故障）
- preferred leader选举
- 分区重新分配

***消费再均衡的原理是什么？（消费者协调器和消费组协调器）***

有一下几种情形会触发再均衡的操作：

- 有新的消费者加入消费组
- 有消费者宕机下线，消费者不一定需要真正下线，例如长时间的GC，网络延迟导致消费者长时间未向GroupCoordinator发送心跳等情况时，GroupCoordinator会认为消费者已经下线
- 有消费者主动退出消费组（发送LeaveGroupRequest请求）。不如客户端调用了unsubscrible() 方法取消某些主题的订阅
- 消费者所对应的GroupCoordinator节点发生了变更
- 消费组所订阅的任一主题或者主题的分区数量发生变化

GroupCoordinator是kafka服务端中用于管理消费组的组件，而消费组客户端中的ConsumerCoordinator组件负责与GroupCoordinator进行交互

***第一阶段（FIND_COORDINATOR）***

消费者需要确定它所属的消费组对应的GroupCoordinator所在的broker，并创建于该broker相互通信的网络连接，如果消费者已经保存了与消费组对应的GroupCoordinator节点的信息，并且与它之间的网络连接是正常的，那么就可以进入第二阶段，否则，就需要想集群中的某个节点发送FindCoordinatorRequest请求来查找对应的GroupCoordinator，这里的“某个节点”并非时集群中的任意节点，而是负载最小的节点

***第二阶段（JOIN_GROUP）***

在成功找到消费组对应的GroupCoordinator之后就进入了加入消费组的阶段，在此阶段的消费者会向GroupCoordinator发送JoinGroupRequest请求，并处理响应

选举消费组的leader

如果消费组内还没有leader，那么第一个加入消费组的消费者即为消费组的leader，如果某一时刻leader消费者由于某些原因退出了消费组，那么会重新选举一个新的leader

选举分区分配策略

1. 收集各个消费者支持的所有分配策略，组成候选集candidates
2. 每个消费者从候选集candidates中找出一个自身支持的策略，为这个策略投上一票
3. 计算候选集中各个策略的选票数，选票数最多的策略即为当前消费组的分配策略

***第三阶段（SYNC_GROUP）***

leader消费者根据在第二阶段中选举出来的分区分配策略来实施具体的分区分配，再次之后需要将分配的方案同步给各个消费者，通过GroupCoordinator这个“中间人”来负责转发同步分配方案的

![1695084384537](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084384537.png)

***第四阶段（HEARTBEAT）***

进入这个阶段之后，消费者中的所有消费者就会处理正常工作状态，在正式消费之前，消费者还需要确定拉取消息的其实位置，假设之前已经将最后的消费位移提取到了GroupCoordinator，并且GroupCoordinator将其保存到了kafka内部的__consumer_offsets主题中，此时消费者可以通过OffsetFetchRequest请求获取上次提交的消费位移并从此处继续消费

消费者通过向GroupCoordinator发送心跳来维持他们与消费组的从属关系，以及他们对分区的所有权关系，主要消费者以正常的时间间隔发送心跳，就认为是活跃的，说明它还在读取分区中的消息，心跳线程是一个独立的线程，可以在轮询消息的空挡发送心跳，如果消费者停止发送心跳时间足够长，则整个会话就会被判定为过期，GroupCoordinator也会认为这个消费者已经死亡，就会触发一次再均衡行为。

***kafka中的幂等性是怎么实现的***

为了实现生产者的幂等性，kafka为此引入了producer id（以下简称PID）和序列号（sequence number）这两个概念。

每个新的生产者实例在初始化的时候都会被分配一个PID，这个PID对用户而言是完全透明的，对于每个PID，消息发送到的每一个分区都有对应的序列号，这些序列号从0开始单调递增。生产者没发送一条消息就会将<PID，分区>对应的序列号的值加1

broker端会在内存中为每一对<PID，分区>维护一个序列号，对于收到的每一条消息，只有当它的序列号的值（SN_new）比broker端中维护的对应的序列号的值（SN_old）大1（即SN_new = SN_old + 1）时，broker才会接受它，如果SN_new < SN_old + 1，那么说明消息被重新写入，broker可以直接将其丢弃，如果SN_new > SN_old + 1，那么说明中间有数据尚未写入，出现了乱序，俺是可能有消息丢失，对一个in的生产者会抛出OurOfOrderSequenceExecption，这个异常是一个严重的异常，后续的诸如send(), beginTransaction(), commitTransaction() 等方法都会抛出IllegalStateException的异常

***多副本下，各个副本中的HW和LEO的演变过程***

某个分区中有3个副本分别为以broker0，broker1，broker2节点中，假设broker0上的副本1位当前分区的leader副本，那么副本2和副本3就是follower副本，整个消息追加的过程可以概括如下：

- 生产者客户端发送消息至leader副本（副本1）中
- 消息被追加到leader副本的本地日志，并且会更新日志的偏移量
- follower副本（副本2和副本3）想leader副本请求同步数据
- leader副本所在的服务器读取本地日志，并更新对应拉取的follower副本的信息
- leader副本所在的服务器将拉取的结果返回给follower副本
- follower副本收到leader副本返回的拉取结果，将消息追加到本地日志中，并更新日志的偏移量信息

某一时刻，leader副本的LEO增加至5，并且所有副本的HW还都为0

![1695084411634](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084411634.png)

***HW：表示了一个特定的消费偏移量，消费者只能拉取到这个offset之前的消息***

***LEO：Log End Offset，它表识当前日志文件中下一条待写入消息的offset***

之后follower副本（不带阴影的方框）想leader副本拉取消息，在拉取的请求中会带有自身的LEO信息，这个LEO信息对应的是FetchRequest请求中的fetch_offset。leader副本返回给follower副本相应的消息，并且还带有自身的HW信息，如上图（右）所示，这个HW信息对应的是FetchResponse中的high_watermark

此时两个follower副本各自拉取到了消息，并更新各自的LEO为3和3，与此同时，follower副本还会更新自身的HW，更新HW的算法是比较当前LEO和leader副本中传送过来的HW的值，去较小值作为自己的HW值，当前两个follower副本的HW都等于0（min(0, 0) = 0）

接下来follower副本年再次请求拉取leader副本中的消息，

![1695084443301](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084443301.png)

此时leader副本收到来自follower副本的FetchRequest请求，其中带有LEO的相关信息， 选取其中的最小值作为新的HW，即min(15, 3, 4) = 3。然后连同消息和HW一起返回FetchResponse给follower副本，如上图（右）所示，注意leader副本的HW是一个很重要的东西，因为它直接影响了分区数据对消费者的可见性

两个follower副本在收到新的消息之后更新LEO并且更新自己的HW为3（min(LEO, 3) =3）

***为什么kafka不支持读写分离***

两个明显的缺点

1. 数据一致性问题：数据从主节点转移到从节点必然会有一个延时的时间窗口，这个时间窗口会导致主从节点之间的数据不一致
2. 延时问题：数据从写入主节点到同步至从节点的过程需要经历网络 → 主节点内存 → 主节点磁盘 → 网络 → 从节点内存 → 从节点磁盘这几个阶段，对延时敏感的应用而言，主写从读的功能并不太适用

对于kafka而言，必要性不是很高，因为在kafka集群中，如果存在多个副本，经过合理的配置，可以让leader副本均匀的分区在各个broker上面，使每个broker上的读写负载都是一样的

***kafka哪些设计让他拥有如此高的性能***

1. 分区

   kafka是个分布式集群的系统，这呢个系统可以包含多个broker，也就是多个服务器实例，每个主题topic会有多个分区，kafka将分区均匀地分配到整个集群中，当生产者想对应主题传送消息，消息通过负载均衡机制传递到不同的分区以减轻单个服务器实例的压力

   一个consumer group中可以有多个consumer，多个consumer可以同时消费不同分区的消息，大大的提高了消费者的并行消费能力，但是一个分区中的消息只能被一个consumer group中的一个consumer消费

2. 网络传输上减少开销

   - 批量发送：在发送消息的时候，kafka不会直接将少量数据发送出去，否则每次发送少量的数据会增加网络传输频率，降低网络传输效率。kafka会先将消息缓存在内存中，当超过一个的大小或超过一定的时间，那么就会将这些消息进行批量发送
   - 端到端压缩：当然网络传输时数据量小也可以减少网络负载，kafka会将这些批量的数据进行压缩，将一批消息打包后进行压缩，发送broker服务器后，最终这些数据还是提供给消费者用，所以数据在服务器上还是保持压缩状态，不会进行解压，而且平凡的压缩和解压也会降低性能，最终还是以压缩的方式传递到消费者手上

3. 顺序读写

   kafka将消息追加到日志文件中，利用了磁盘的顺序读写，来提高读写效率

4. 零拷贝技术

   零拷贝将文件内容从磁盘通过DMA引擎复制到内核缓冲区，而且没有把数据复制到socket缓冲区，只是将数据位置和长度信息的描述符复制到了socket缓存区，然后直接将数据传输到网络接口，最后发送。这样大大减小了拷贝的次数，提高了效率。kafka正是调用linux系统给出的sendfile系统调用来使用零拷贝。Java中的系统调用给出的是FileChannel.transferTo接口。

5. 优秀的文件存储机制

   如果分区规则设置得合理，那么所有的消息可以均匀地分布到不同的分区中，这样就可以实现水平扩展。不考虑多副本的情况，一个分区对应一个日志（Log）。为了防止 Log 过大，Kafka 又引入了日志分段（LogSegment）的概念，将 Log 切分为多个 LogSegment，相当于一个巨型文件被平均分配为多个相对较小的文件，这样也便于消息的维护和清理。

   ![1695084464255](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084464255.png)

   Kafka 中的索引文件以稀疏索引（sparse index）的方式构造消息的索引，它并不保证每个消息在索引文件中都有对应的索引项。每当写入一定量（由 broker 端参数 log.index.interval.bytes 指定，默认值为4096，即 4KB）的消息时，偏移量索引文件和时间戳索引文件分别增加一个偏移量索引项和时间戳索引项，增大或减小 log.index.interval.bytes 的值，对应地可以增加或缩小索引项的密度。

***kafka怎么保证消息的可靠性传输***

场景：kafka的某个broker宕机了，然后重新选举partition的leader，要是此时其他的follower刚好还有些数据没有同步，结果此时leader挂了，然后选举某个follower成leader之后，就少了一些数据

要求设置如下4个参数

- 给topic设置replication.factor参数：这个值必须大于1，要求每个partition必须有至少2个副本
- 在kafka服务端设置min.insync.replicas参数：这个值必须大于1，这个是要求一个leader至少感知到至少一个follower还跟自己保持联系，没掉队，这样才能确保leader挂了还有一个follower
- 在producer端设置acks=all，这个是要求每条数据，必须是写入所有replica之后才能认为是写成功了
- 在producer端设置retries=MAX（无限重试）：这个是要求一旦写入失败，就无限重试，卡在这里

生产环境按照上述要求配置，这样配置之后，至少在kafka broker端就可以保证在leader所在broker发生故障，进行leader切换时，数据不会丢失

按照上述设置之后，生产者一定不会丢失数据，设置acks=all，leader接收到消息，所有的follower都同步到了消息之后，才认为本次写入成功，如果没有满足这个条件，生产者会自动不断的重试，重试无限次。

***kafka分区***

***场景描述***

kafka使用分区将topic的消息打散到多个分区分布保存在不同的broker上，实现了producer和consumer消息处理的高吞吐量，kafka的producer和consumer都可以多线程地并行操作，是每个线程处理的是一个分区的数据，因此分区设计上是调优kfaka并行度的最小单元，对于producer而言，它实际上是用多个线程并发地向不同分区所在的broekr发起socket连接同时給这些分区发送消息；而consumer，同一消费组内的consumer线程都被指定topic的某一分区进行消费

***分区是不是越多越好***

并不是，因为每个分区都有自己的开销

1. 客户端/服务端需要使用功能的内存就越多

   kafka0.8.2之后，在客户端produer有个参数batch.size，默认是16KB，它会为每个分区缓存消息，一旦满了就打包将消息批量发出，看上去这是能够提升性能的设计。不过很显然，因为这个参数是分区级别的，如果分区数越多，这部分缓存所需的内存占用也会更多，假设有10000个分区，按照默认设置，这部分缓存需要占用157MB内存，而consumer端，抛开获取数据所需的内存不说，只说线程的开销。如果假设有10000个分区，同时consumer线程数要匹配分区数（大部分情况下是最佳的消费吞吐量配置）的话，那么在consumer client就要创建10000个线程，也需要创建10000个socket去获取分区数据，这里面的线程且混得开销本身已经不容小觑了。

   服务器端的开销也不小，服务器端的很多组件都在内存中维护了分区级别的缓存，如controller，fetchManager等，因此分区数越多，这种缓存的成本就越大

2. 文件句柄的开销

   每个分区在底层文件系统都有属于自己的一个目录。该目录下通常会有两个文件：base_offset.log和base_offset.index。Kafak的controller和ReplicaManager会为每个broker都保存这两个文件句柄(file handler)。很明显，如果分区数越多，所需要保持打开状态的文件句柄数也就越多，最终可能会突破你的ulimit -n的限制。

3. 降低高可用性

   kafka通过副本（replica）机制保证高可用。具体做法就是每个分区保存若干副本（replica_factor指定副本数）。每个副本保存在不同的broker上，其中的一个副本充当leader副本，负责处理producer和consumer请求，其他副本充当follower副本，由kafka controller负责保证与leader的同步。如果leader所在的broker挂掉了，controller会检测到然后在zookeeper的帮助下重选出新的leader—这中间会有短暂的不可用时间窗口，虽然大部分情况下可能只是几毫秒级别。但如果你有10000个分区，10个broker，也就是说平均每个broker上有1000个分区。此时这个broker挂掉了，那么zookeeper和controller需要立即对这1000个分区进行leader选举。比起很少的分区leader选举而言，这必然要花更长的时间，并且通常不是线性累加的。如果这个broker还同时是controller情况就更糟了。

   ***如何确定分区的数量？***

   可以遵循一定的不走来尝试确定分区数：创建一个只有一个分区的topic，然后测试这个topic的producer吞入量和consumer吞吐量，假设它们的值分别是Tp和Tc，单位可以是MB/s，然后假设总的目标吞吐量是Tt，那么分区数=Tt/max(Tp, Tc)

   说明，Tp表示producer的吞吐量，测试producer通常是很容易的，因为它的逻辑非常简单，就是直接发送消息到kafka就行了，Tc表示consumer的吞入量，测试Tc通常与应用的关系更大， 因为Tc取决于你拿到消息之后执行的操作，因此Tc的测试通常也要麻烦一些

   ***一条消息如何知道要被发送到哪个分区？***

   ***按照key分区***

   默认情况下，kafka根据传递消息的key来进行分区的分配，即hash(key) % numPartitions

   ```scala
   def partition(key: Any, numPartitions: Int): Int = {
   	Utils.abs(key.hashCode) % numPartitions
   }
   ```

   这保证了相同key的消息一定会被路由到相同的分区，key为null时，从缓存中取分区id或者随机取一个，如果你没有指定key，那么kafka是如何确定这条消息去往哪个分区的呢？

   ```scala
   if(key == null){
   	val id = sendPartitionPerTopicCache.get(topic) // 先看看kafka有没有缓存的现成的分区ID
   	id match {
   		case Some(partitionId) => 
   				partitionId
   		case None =>
   				val availablPartitions = topicPartitionList.filter(_.leaderBrokerIdOpt.isDefined)
   				if(availablePartitions.isEmpty)
   						throw new LeaderNotAvailableException("No leader for any partition in this topic " + topic)
   				val index = Utils.abs(Random.nextInt) % availabltPartitions.size  // 从中随机挑一个
   				val partitionId = availablePartitions(index).partitionId
   				sendPartitionPerTopicCache.put(topic, partitionId) // 更新缓存以备下一次直接使用
   				
   	}
   }
   ```

   不指定key时，kafka几乎就是随机找一个分区发送无key的消息，然后把这个分区号加入到缓存中以备后面直接使用，kafka本身也会清空该缓存（默认每10分钟或每次请求topic元数据时）

   ***Consumer个数和分区数有什么关系？***

   topic下的一个分区只能被同一个consumer group下的一个consumer线程来消费，但反之并不成立，即一个consumer线程可以消费多个分区的数据，比如kafka提供的consoleConsumer，默认就只是一个线程来消费所有分区的数据

   ![1695084488847](C:\Users\star\AppData\Roaming\Typora\typora-user-images\1695084488847.png)

   所以，如果分区数是N，那么最好线程数也保持为N，这样通常能够达到最大的吞吐量，超过N的配置只是浪费系统资源，因为多出的线程不会被分配到任何分区

***kafka常见的导致差农夫消费原因和解决方案***

***问题分析***

导致kafka的重复消费问题原因在于，已经消费了数据，但是offset还没来得及提交（比如kafka没有或者不知道该数据以及被消费）

以下场景导致kafka重复消费：

- 强行kill线程，导致消费后的数据，offset没有提交（消费系统宕机，重启等）

- 设置offset为自动提交，关闭kafka时，如果在close之前，调用consumer.unsubscribe()则有可能部分offset没提交，下次重启会重复消费

  ```java
  try {
      consumer.unsubscribe();
  } catch (Exception e) {
  }
  
  try {
      consumer.close();
  } catch (Exception e) {
  }
  ```

  ***解决方法：设置offset自动提交为false***

  ```java
  Properties props = new Properties();
  props.put("bootstrap.servers", "localhost:9092");
  props.put("group.id", "test");
  props.put("enable.auto.commit", "false");
  ```

  设置enable.auto.commit=true之后，kafka会保证在开始调用poll方法时，提交上次poll返回的所有消息，从顺序上来说，poll方法的逻辑是先提交上一批消息的位移，在处理下一批消息，因此，他能保证不出现消费丢失的情况

- （重复消费最常见的原因）：消费后的数据，offset还没有提交时，partition就断开连接，比如，通常会遇到消费的数据，处理很好使，导致超过了kafka的session timeout时间（0.10.x版本默认是30s），那么就会Rebalance重平衡，此时有一定几率offset还没有提交，它会导致重平衡之后的重复消费

- 当消费者重新分配partition的时候，可能出现从头开始消费的情况，导致重发问题

- 当消费者消费的速度很慢的时候，可能在一个session周期内还未完成，导致心跳机制检测报告出问题

- 并发很大，可能在规定时间内（session.time.out默认30s）内没有消费完，就会可能导致Rebalance重平衡，导致一部分offset自动提交失败，然后重平衡后重新消费。

***问题描述***

我们系统压测过程中出现下面问题：异常rebalance，而且平均间隔3到5分钟就会触发rebalance，分析日志发现比较严重。错误日志如下：

```java
08-09 11:01:11 131 pool-7-thread-3 ERROR [] - 
commit failed 
org.apache.kafka.clients.consumer.CommitFailedException: Commit cannot be completed since the group has already rebalanced and assigned the partitions to another member. This means that the time between subsequent calls to poll() was longer than the configured max.poll.interval.ms, which typically implies that the poll loop is spending too much time message processing. You can address this either by increasing the session timeout or by reducing the maximum size of batches returned in poll() with max.poll.records.
        at org.apache.kafka.clients.consumer.internals.ConsumerCoordinator.sendOffsetCommitRequest(ConsumerCoordinator.java:713) ~[MsgAgent-jar-with-dependencies.jar:na]
        at org.apache.kafka.clients.consumer.internals.ConsumerCoordinator.commitOffsetsSync(ConsumerCoordinator.java:596) ~[MsgAgent-jar-with-dependencies.jar:na]
        at org.apache.kafka.clients.consumer.KafkaConsumer.commitSync(KafkaConsumer.java:1218) ~[MsgAgent-jar-with-dependencies.jar:na]
        at com.today.eventbus.common.MsgConsumer.run(MsgConsumer.java:121) ~[MsgAgent-jar-with-dependencies.jar:na]
        at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149) [na:1.8.0_161]
        at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624) [na:1.8.0_161]
        at java.lang.Thread.run(Thread.java:748) [na:1.8.0_161]
```

这个错误时，消费者在处理完一批poll的消息后，在同步提交偏移量给broker时报的错，初步分析是当前消费组线程消费的分区已经被broker给回收了，因为kafka认为这个消费者死了，那么为什么呢？

***问题分析***

[这里涉及到的问题时消费者在创建时会有一个max.poll.interval.ms](http://xn--max-p18doh86c1xk1eo1mlplinw7etda569att7ama9910bl09a3o4c27ko3jfvxg6n.poll.interval.ms)（默认时间间隔时间为300s）该属性意思是kafka消费者每一轮poll()调用之间的最大延迟，消费者在获取更多记录之前可以空闲的时间量的上限，如果此超时时间期满之前poll()没有被再次调用，则消费者被视为失败，并且分组将重新平衡Rebalance，一般将分区重新分配给别的成员

处理重复数据

因为offset此时已经不准确了，生成环境不能直接去修改offset偏移量

所以重新指定一个消费组（[group.id](http://group.id) = order-consuemr_group），然后指定auto-offset-reset=latest这样我就只需要重启我的服务，而不需要动kafka和zookeeper了

```java
consumer
spring.kafka.consumer.group-id=order_consumer_group
spring.kafka.consumer.key-deserializer=org.apache.kafka.common.serialization.StringDeserializer
spring.kafka.consumer.value-deserializer=org.apache.kafka.common.serialization.StringDeserializer
spring.kafka.consumer.enable-auto-commit=falsespring.kafka.consumer.auto-offset-reset=latest
```

如果想要消费者从头开始消费某个topic的全量数据，可以重新指定一个全新的group.id=new_group，然后指定auto-offset-reset=earliest即可

***kafka索引设计***

kafka建立的这种索引也就是稀疏索引，即建立较少offset的索引使用较少的内存，但是由于offset的所有建立的不完全，即查询命中可能消耗更多的时间

***kafka消费者***

在kafka中，某些topic的主题拥有数百万甚至千万的消息量，如果仅仅靠这个消费者进程消费，那么消费速度会非常慢，所以我们需要使用kafka提供的消费组功能，同一个消费组的多个消费组就能分布到多个物理机器上加速消费

每个消费者都会有一个独一无二的消费组id来标记自己。每一个消费者group可能有一个或者多个消费者，对于当前消费组来说，topic中每条数据只要被消费组内任何一条消费组消费一次，那么这条数据就可以认定被当前消费组消费成功

kafka消费组有如下三个特征

- 每个消费组有一个或者多个消费者
- 每个消费组拥有一个唯一性的标识id
- 消费组在消费topic的时候，topic的每个partition只能分配给一个消费者

```bash
./kakfka-topics.sh --create --zookeeper localhost:2181 
	--replication-factor 1 --partitions 8 -- topic helloKafka
```

***消费组offset***

1. 手动提交

   在一批消息消费完成之后，不要忘了提交offset，否则会导致消费者重复消费相同的消息，消费者在被关闭的的时候，消费者也会自动提交offset，所以如果我们判断消费者完成消费，我们可以使用try-finally关闭消费者，手动提交offset两种方式，同步和异步方式

   ***同步提交***

   ```java
   consumer.commitSync()
   ```

   所谓同步，指的是consumer会一直等待提交offset成功，在此期间不能继续拉取以及消费消息，如果提交失败，consumer会一直重复尝试提交，知道超时，默认时间为60s

   ***异步提交***

   ```java
   consumer.commitAsync()
   ```

   异步提交不会阻塞消费者线程，提交失败的时候不会进行重试，但是我们可以为异步提交创建一个监听器，在提交失败的时候进行重试

   ```java
   consumer.commitAsync(new RetryOffsetCommitCallback(consumer));
   ```

   offset失败重试回调监听器

   ```java
   public class RetryOffsetCommitCallback implements OffsetCommitCallback {
   	privat static Logger LOGGER = LoggerFactory.getLogger(RetryOffsetCommitCallback.class);
   	
   	private KafkaConsumer<String, String> consumer;
   	
   	public RetryOffsetCommitCallback(KafkaConsumer<String, String> consumer){
   		this.consumer = consumer;
   	}
   
   	@Override
   	public void onComplete(Map<TopicPartition, OffsetAndMetadata> offsets, Exception exception){
   		if(exception != null){
   			LOGGER.info(exception.getMessage(), exception);
   			consumer.commitAsync(offsets, this);
   		}
   	}
   }
   ```

   ***自动提交***

   在大多数情况下，为了避免消息被重复消费，我们使用自动提交机制，我们通过如下参数进行配置

   ```java
   props.put("enable.auto.commit", "true");
   props.put("auto.commit.interval.ms", "1000");
   ```

   在上述参数配置情况下，consumer会以每秒一次的频率定期的持久化offset，看到这笔者有一个疑问，如果消费者意外宕机，那么距离上一次提交的offset又会被重新消费，如果业务和钱相关，那么就会有大麻烦，所以消费者消费消息的时候，需要实现幂等性，关于幂等性的话题，笔者未来写一篇文章介绍如何实现消费幂等性。

   除了以固定频率提交offset之外，kafka在关闭consumer的时候也会提交offset

   ```java
   consumer.close()
   ```

   就版本的kafka会将消费偏移提交到zookeeper中，提交路径如下

   ```java
   /consuemrs/ConsumerGroup/offsets/TestTopic/0
   ```

   其中ConsumerGroup代表具体的消费组，而TestTopic代表消费主题，末尾的数字代表分区号。但是Zookeeper作为分布式协调系统，不适合作为频繁读写工具。于是新版本的kafka将消费位移存储在kafka内部的主题_consumer_offsets中。

   在一个大型系统中，会有非常多的消费组，如果这些消费组同时提交位移，Broker服务器会有比较大的负载，所以kafka的_consumer_offsets拥有50个分区，这样_consumer_offsets的分区就能均匀分布到不同的机器上，即使多个消费组同时提交offset，负载也能均匀的分配到不同的机器上

   消费组在提交唯一的时候，消费组将位移提交到哪个分区呢？消费组通过如下公式确定

   ```java
   Math.abs(hash(groupID)) % numPartitions
   ```

   消费者会定期的向这个partition提交唯一，那么同一个消费组，同一个topic，同一个paritiotn提交的位移会不会越来越多呢？不会，kafka有压缩机制，会定期压缩_consumer_offsets，压缩的依据是消息message中包含的key（即groupID + topic + 分区id），kafka会合并相同的key，只留下最新消费组

   ***手动提交 vs 自动提交***

   如何选择手动提交和自动提交？自动提交的优点在于实现简单，但是消息可能会发生丢失，举一个场景，比如consumer从broker拉去了500条消息，此时正在消费100条，但是自动提交机制可能就将offset提交了，如果此时consumer宕机，那么当前的consumerGroup还有400条消息就消费不到了，如果消息特别重要绝对不允许丢失，那么应该使用手动提交offset

***Rebalance流程***

Coordinator发生Rebalance的时候，Coordinator并不会主动通知组内所有Consumer重新加入组，而是当Consumer想Coordinator发送心跳的时候，Coordinator将Rebalance的状况通过心跳响应告知Consumer，Rebalance机制整体步骤分为，一个是Joining the Group，另一个是分配Synchronizing Group State

***3.1 Joining the Group***

在当前步骤中，所有的消费者会和Coordinator交互，请求Coordinator加入当前消费组，Coordinator会从所有的消费者中选择一个消费者作为leader consumer，选择的算法是随机选择

***3.2 Synchronizing Group State***

leader Consumer从Coordinator获取所有的消费者的信息，并将消费组订阅的partition分配结果封装为SyncGroup请求，需要注意的是leader Consumer不会直接与组内其他的消费者交互，leader Consumer会将SyncGroup发送给Coordinator，Coordinator再将分配结果发送给各个Consumer，分配partition有以下三种策略RangeAssignor，RoundRobinAssignor，StickyAssignor

如果leader consumer因为一些特殊原因导致分配分区失败（Coordinator通过超时的方式检测），那么Coordinator会重新要求所有的Consumer重新进行Joining the Group状态

***Coordinator生命周期***

为了更好的了解Coordinator的职责以及Rebalance机制，在Coordinator的生命周期中一共有5种状态

- Down：Coordinator不会维护任何消费组状态
- Initialize：Coordinator处于初始化状态，Coordinator从Zookeeper中读取相关的消费组数据，这个时候Coordinator对接受到消费组心跳或者加入组的请求都会返回错误
- Stable：Coordinator处理消费组心跳请求，但是还未开始初始化generation，Coordinator正在等待消费组加入组的请求
- Joining：Coordinator正在处理组内成员加入组的请求
- AwaitingSync：等待leader consumer分配分区，并将分区分配结果发送给各个consumer

这5个状态相互转换流程图如下

 ![图片](https://mmbiz.qpic.cn/mmbiz_jpg/UdK9ByfMT2NM1GHiaI3ZrUlABSZvr5Hab6zKtBlKAN3OgVBtoamDiaLwGeDpKIia9DnDGRzwX7rbCSUSibB0uNqrJw/640?wx_fmt=jpeg&tp=wxpic&wxfrom=5&wx_lazy=1&wx_co=1) 



***Leader Consumer***

leader Consumer是Coordinator在Joining the Group步骤的时候随机选择的，Leader Consumer负责组内各个Consumer的partition的分配，除此之外Leader Consumer还负责整个消费组订阅的主题的监控，Leader Consumer会定期更新消费组订阅的主题信息，一旦发现主题信息发生了变化，Leader Consumer会通知Coordinator触发Rebalance机制。

