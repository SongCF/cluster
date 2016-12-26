# 所有
all: deps
	rebar compile

# 获取依赖
deps:
	rebar get-deps


# 获取依赖
udeps:
	rebar update-deps

# 清楚
clean:
	rebar clean

# 测试
test:
	rebar eunit


.PHONY:deps test proto
