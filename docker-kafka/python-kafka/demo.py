def inner(result, data, diff_set):
    flag = False
    for index, _ in enumerate(result):
        section = set(_).intersection(set(data))
        if len(section) != 0:
            diff = list(set(data).intersection(set(diff_set)))
            data = [x for x in data if x not in diff]
            diff_set.extend(list(section))
            result[index] = list(set(result[index]).symmetric_difference(set(data)))
            flag = True
            break
    if flag:
        result = sec(result)
    return result, flag


def sec(datas):
    result = [datas[0]]
    diff_set = []
    for data in datas[1:]:
        result, flag = inner(result, data, diff_set)
        if not flag:
            result.append(list(set(data)))
    return result


# datas = [[1, 2, 3], [3, 4, 5], [6, 7, 8], [1, 6, 12], [1, 2, 3], [11, 13, 14], [14, 15, 16]]
datas = [[1, 2, 3], [2, 3, 4], [4, 5, 6], [7, 8, 9], [1, 2, 3], [6, 7, 8]]
print(sec(datas))
