-- requirement 1
-- we have user access data as below
-- 	userId  visitDate   visitCount
-- 	 u01     2017/1/21       5
-- 	 u02     2017/1/23       6
-- 	 u03     2017/1/22       8
-- 	 u04     2017/1/20       3
-- 	 u01     2017/1/23       6
-- 	 u01     2017/2/21       8
-- 	 U02     2017/1/23       6
-- 	 U01     2017/2/22       4
-- It is required to use sql to count the cumulative access times of each user,
-- as shown in the following table:
-- 	userId    month     subtotal  accumulation
-- 	 u01     2017-01       11           11
-- 	 u01     2017-02       12           23
-- 	 u02     2017-01       12           12
-- 	 u03     2017-01       8            8
-- 	 u04     2017-01        3           3

create table if not exists test_sql.test1
(
    userId
    string,
    visitDate
    string,
    visitCount
    int
) row format delimited fields terminated by "\t";


insert into table test_sql.test1 values ( 'u01', '2017/1/21', 5 ), ( 'u02', '2017/1/23', 6 ), ( 'u03', '2017/1/22', 8 ), ( 'u04', '2017/1/20', 3 ), ( 'u01', '2017/1/23', 6 ), ( 'u01', '2017/2/21', 8 ), ( 'u02', '2017/1/23', 6 ), ( 'u01', '2017/2/22', 4 );


--
select t2.userId,
       t2.visitMonth,
       subtotal_visit_count,
       sum(subtotal_visit_count) over (partition BY userId ORDER BY visitMonth) as accumulation
from (
         select userId,
                DATE_FORMAT(REGEXP_REPLACE(visitDate, '/', '-'), 'yyyy-MM') AS visitMonth,
                SUM(visitCount)                                             AS subtotal_visit_count
         from test1
         group by userId, visitMonth
     ) t2
order by t2.userId, t2.visitMonth;


create table if not exists test_sql.test1_result
(
    userId
    string,
    visitMonth
    string,
    subtotal_visit_count
    int,
    accumulation
    int
) row format delimited fields terminated by "\t";

insert into table test1_result
select t2.userId,
       t2.visitMonth,
       subtotal_visit_count,
       sum(subtotal_visit_count) over (partition BY userId ORDER BY visitMonth) as accumulation
from (
         select userId,
                visitMonth,
                sum(visitCount) as subtotal_visit_count
         from (
                  select userId,
                         date_format(regexp_replace(visitDate, '/', '-'), 'yyyy-MM') as visitMonth,
                         visitCount
                  from test1
              ) t1
         group by userId, visitMonth
     ) t2
order by t2.userId, t2.visitMonth;



-- requirement 2
-- There are 500000 Jindong stores, and each customer visitor will generate an access log when visisting any product in
-- any store. The name of the table stored in the access log is visit, the user id of the visitor is user_id, and the
-- name of the shop visited is shop. The data is as follows
-- 				u1	a
-- 				u2	b
-- 				u1	b
-- 				u1	a
-- 				u3	c
-- 				u4	b
-- 				u1	a
-- 				u2	c
-- 				u5	b
-- 				u4	b
-- 				u6	c
-- 				u2	c
-- 				u1	b
-- 				u2	a
-- 				u2	a
-- 				u3	a
-- 				u5	a
-- 				u5	a
-- 				u5	a
-- count the UV(number of visitors) of each store
-- count the visitor information of the top 3 visits to each store. Output store name, visitor id, number of visits.

create table if not exists test_sql.test2
(
    user_id
    string,
    shop
    string
) row format delimited fields terminated by '\t';

insert into test_sql.test2
values ('u1', 'a'),
       ('u2', 'b'),
       ('u1', 'b'),
       ('u1', 'a'),
       ('u3', 'c'),
       ('u4', 'b'),
       ('u1', 'a'),
       ('u2', 'c'),
       ('u5', 'b'),
       ('u4', 'b'),
       ('u6', 'c'),
       ('u2', 'c'),
       ('u1', 'b'),
       ('u2', 'a'),
       ('u2', 'a'),
       ('u3', 'a'),
       ('u5', 'a'),
       ('u5', 'a'),
       ('u5', 'a');

select shop,
       count(distinct user_id) as uv_count
from test_sql.test2
group by shop;


select t2.shop,
       t2.user_id,
       t2.rank
from (
         select t1.*,
                row_number() over(partition by shop order by cnt desc) as rank
         from (
                  select shop,
                         user_id,
                         count(*) as cnt
                  from test2
                  group by shop, user_id
              ) t1
     ) t2
where rank <= 3;



-- requirement 3
-- A known table stg.order has the following fields: date、order_id、user_id、amount
-- please give sql for statistics:
-- Data sample: 2017-01-01,10029028,1000003251,33.57。
-- Give the number of orders, number of users, and total transaction amount for each month in 2017.
-- Give the number of new customers in November 2017(referring to the first order in November).

create table if not exists test_sql.test3
(
    dt
    string,
    order_id
    string,
    user_id
    string,
    amount
    decimal
(
    10,
    2
)
    ) row format delimited fields terminated by '\t';
INSERT INTO TABLE test_sql.test3 VALUES ('2017-01-01','10029028','1000003251',33.57);
INSERT INTO TABLE test_sql.test3 VALUES ('2017-01-01','10029029','1000003251',33.57);
INSERT INTO TABLE test_sql.test3 VALUES ('2017-01-01','100290288','1000003252',33.57);
INSERT INTO TABLE test_sql.test3 VALUES ('2017-02-02','10029088','1000003251',33.57);
INSERT INTO TABLE test_sql.test3 VALUES ('2017-02-02','100290281','1000003251',33.57);
INSERT INTO TABLE test_sql.test3 VALUES ('2017-02-02','100290282','1000003253',33.57);
INSERT INTO TABLE test_sql.test3 VALUES ('2017-11-02','10290282','100003253',234);
INSERT INTO TABLE test_sql.test3 VALUES ('2018-11-02','10290284','100003243',234);


select t1.mon,
       count(t1.order_id) as order_cnt,
       count(t1.user_id)  as user_cnt,
       sum(amount)        as total_amount
from (
         select order_id,
                user_id,
                amount,
                date_format(dt, 'yyyy-MM') as mon
         from test3
         where date_format(dt, 'yyyy') = '2017'
     ) t1
group by t1.mon;

select count(distinct user_id) as new_customer_cnt
from test3
where date_format(dt, 'yyyy-MM') = '2017-11'
  and user_id not in (
    select user_id
    from test3
    where date_format(dt, 'yyyy-MM-dd') < '2017-11-01'
);


-- There is a 50 million user file(user_id, name, age), a record file of 200 million users watching
-- movies(user_id, url), sorted according to the number of times the age group watched movies?

create table if not exists test_sql.test4User
(
    user_id
    string,
    name
    string,
    age
    int
);
create table if not exists test_sql.test4Log
(
    user_id
    string,
    url
    string
);

INSERT INTO TABLE test_sql.test4User VALUES('001','u1',10);
INSERT INTO TABLE test_sql.test4User VALUES('002','u2',15);
INSERT INTO TABLE test_sql.test4User VALUES('003','u3',15);
INSERT INTO TABLE test_sql.test4User VALUES('004','u4',20);
INSERT INTO TABLE test_sql.test4User VALUES('005','u5',25);
INSERT INTO TABLE test_sql.test4User VALUES('006','u6',35);
INSERT INTO TABLE test_sql.test4User VALUES('007','u7',40);
INSERT INTO TABLE test_sql.test4User VALUES('008','u8',45);
INSERT INTO TABLE test_sql.test4User VALUES('009','u9',50);
INSERT INTO TABLE test_sql.test4User VALUES('0010','u10',65);
INSERT INTO TABLE test_sql.test4Log VALUES('001','url1');
INSERT INTO TABLE test_sql.test4Log VALUES('002','url1');
INSERT INTO TABLE test_sql.test4Log VALUES('003','url2');
INSERT INTO TABLE test_sql.test4Log VALUES('004','url3');
INSERT INTO TABLE test_sql.test4Log VALUES('005','url3');
INSERT INTO TABLE test_sql.test4Log VALUES('006','url1');
INSERT INTO TABLE test_sql.test4Log VALUES('007','url5');
INSERT INTO TABLE test_sql.test4Log VALUES('008','url7');
INSERT INTO TABLE test_sql.test4Log VALUES('009','url5');
INSERT INTO TABLE test_sql.test4Log VALUES('0010','url1');

select t2.age_phase,
       sum(t1.cnt) as view_cnt
from (
         select user_id,
                count(*) as cnt
         from test4Log
         group by user_id
     ) t1
         join(
    select user_id,
           case
               when age <= 10 and age > 0 then '0-10'
               when age <= 20 and age > 10 then '10-20'
               when age > 20 and age <= 30 then '20-30'
               when age > 30 and age <= 40 then '30-40'
               when age > 40 and age <= 50 then '40-50'
               when age > 50 and age <= 60 then '50-60'
               when age > 60 and age <= 70 then '60-70'
               else '70以上' END as age_phase
    from test4User
) t2
             on t1.user_id = t2.user_id
group by t2.age_phase

-- The log is as follows, please write the code to get the total and average age of all users and
-- active users. (Active users refer to users who have access records for two consecutive days.)
--     dt       user   age
-- 2019-02-11, test_1, 23
-- 2019-02-11, test_2, 19
-- 2019-02-11, test_3, 39
-- 2019-02-11, test_1, 23
-- 2019-02-11, test_3, 39
-- 2019-02-11, test_1, 23
-- 2019-02-12, test_2, 19
-- 2019-02-13, test_1, 23
-- 2019-02-15, test_2, 19
-- 2019-02-16, test_2, 19

create table if not exists test_sql.test5
(
    dt
    string,
    user_id
    string,
    age
    int
) row format delimited fields terminated by ',';

INSERT INTO TABLE test_sql.test5 VALUES ('2019-02-11','test_1',23);
INSERT INTO TABLE test_sql.test5 VALUES ('2019-02-11','test_2',19);
INSERT INTO TABLE test_sql.test5 VALUES ('2019-02-11','test_3',39);
INSERT INTO TABLE test_sql.test5 VALUES ('2019-02-11','test_1',23);
INSERT INTO TABLE test_sql.test5 VALUES ('2019-02-11','test_3',39);
INSERT INTO TABLE test_sql.test5 VALUES ('2019-02-11','test_1',23);
INSERT INTO TABLE test_sql.test5 VALUES ('2019-02-12','test_2',19);
INSERT INTO TABLE test_sql.test5 VALUES ('2019-02-13','test_1',23);
INSERT INTO TABLE test_sql.test5 VALUES ('2019-02-15','test_2',19);
INSERT INTO TABLE test_sql.test5 VALUES ('2019-02-16','test_2',19);

-- SELECT SUM(age) AS total_age
-- FROM (
--     SELECT DISTINCT user_id, age
--     FROM test5
-- ) subquery;

select sum(total_user_cnt)     as total_user_cnt,
       sum(total_user_avg_age) as total_user_avg_age,
       sum(two_days_cnt)       as two_days_cnt,
       sum(avg_age)            as avg_age
from (
         select 0                                             total_user_cnt,
                0                                             total_user_avg_age,
                count(*)                                   AS two_days_cnt,
                cast(sum(age) / count(*) AS decimal(5, 2)) AS avg_age
         from (select user_id,
                      max(age) as age
               from (
                        select user_id,
                               max(age) as age
                        from (
                                 select user_id,
                                        age,
                                        date_sub(dt, rank) flag
                                 from (
                                          select dt,
                                                 user_id,
                                                 max(age) as  age,
                                                 row_number() over(partition by user_id order by dt) rank
                                          from test5
                                          group by dt, user_id
                                      ) t1
                             ) t2
                        group by user_id, flag
                        having count(*) >= 2
                    ) t3
               group by user_id
              )
         union all
         select count(*)                                   total_user_cnt,
                cast(sum(age) / count(*) as decimal(5, 2)) total_user_avg_age,
                0                                          two_days_cnt,
                0                                          avg_age
         from (
                  select user_id,
                         max(age) as age
                  from test5
                  group by user_id
              ) t5
     ) t6;


SELECT user_id,
       dt,
       age,
       LAG(dt) OVER (PARTITION BY user_id ORDER BY dt) AS prev_dt
FROM test5

SELECT COUNT(DISTINCT user_id)                                        AS total_users,
       COUNT(DISTINCT CASE WHEN prev_dt IS NOT NULL THEN user_id END) AS active_users,
       AVG(age)                                                       AS average_age
FROM (
         SELECT user_id,
                dt,
                age,
                LAG(dt) OVER (PARTITION BY user_id ORDER BY dt) AS prev_dt
         FROM test5
     );