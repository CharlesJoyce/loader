part of '../loader.dart';

enum LoaderType { loading, error, empty }

mixin AutoLoadMoreMixin<T> on Model {
  @protected
  final List<T> _data = [];

  bool _more = true;

  ///has more comments
  bool get hasMore => _more;

  int _offset = 0;

  CancelableOperation _autoLoadOperation;

  @protected
  Future<Result<List<T>>> loadData(int offset);

  int get offset => _offset;

  dynamic error;

  List get items {
    final items = List.from(_data);
    if (error != null) {
      items.add(LoaderType.error);
      return items;
    }
    if (_autoLoadOperation != null) {
      items.add(LoaderType.loading);
      return items;
    }

    if (items.isEmpty) {
      return const [LoaderType.empty];
    }
    return items;
  }

  int get size => items.length;

  ///
  /// load more items
  ///
  /// [notification] use notification to check is need load more items
  ///
  void loadMore({ScrollEndNotification notification}) {
    if (error != null) {
      return;
    }

    if (notification != null &&
        (!_more ||
            notification.metrics.extentAfter > 500 ||
            _autoLoadOperation != null)) {
      return;
    }

    final offset = this.offset;
    _autoLoadOperation =
        CancelableOperation<Result<List<T>>>.fromFuture(loadData(offset))
          ..value.then((r) {
            if (r == null || r.isError) {
              error = r == null ? "result is null" : r.asError.error.toString();
            } else {
              final result = LoadMoreResult._from(r.asValue);
              _more = result.hasMore;
              _offset += result.loaded;
              _data.addAll(result.value);

              onDataLoaded(offset, result);
            }
          }).whenComplete(() {
            notifyListeners();
            _autoLoadOperation = null;
          });
    notifyListeners();
  }

  @protected
  void onDataLoaded(int offset, LoadMoreResult result) {}

  ///create builder for [ListView]
  IndexedWidgetBuilder createBuilder(List data,
      {IndexedWidgetBuilder builder}) {
    return (context, index) {
      final widget = buildItem(context, data, index) ??
          (builder == null ? null : builder(context, index));
      assert(widget != null, 'can not build ${data[index]}');
      return widget;
    };
  }

  IndexedWidgetBuilder obtainBuilder() {
    return (context, index) {
      return buildItem(context, items, index);
    };
  }

  ///build item for position [index]
  ///
  /// return null if you do not care this position
  ///
  @protected
  Widget buildItem(BuildContext context, List list, int index) {
    if (list[index] == LoaderType.loading) {
      return buildLoadingItem(context, list.length == 1);
    } else if (list[index] == LoaderType.error) {
      return buildErrorItem(context, list.length == 1);
    } else if (list[index] == LoaderType.empty) {
      return buildEmptyWidget(context);
    }
    return null;
  }

  @protected
  Widget buildLoadingItem(BuildContext context, bool empty) {
    return SimpleLoading(height: empty ? 200 : 50);
  }

  @protected
  Widget buildErrorItem(BuildContext context, bool isEmpty) {
    final retry = () {
      error = null;
      loadMore();
    };
    if (isEmpty) {
      return SimpleFailed(
        retry: retry,
        message: error.toString(),
      );
    } else {
      return Container(
        height: 56,
        child: Center(
          child: RaisedButton(
            onPressed: retry,
            child: Text("加载失败！点击重试"),
            textColor: Theme.of(context).primaryTextTheme.body1.color,
            color: Theme.of(context).errorColor,
          ),
        ),
      );
    }
  }

  @protected
  Widget buildEmptyWidget(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: 200),
      child: Center(child: Text('暂无数据...')),
    );
  }
}

class LoadMoreResult<T> extends ValueResult<List<T>> {
  ///已加载的数据条目
  final int loaded;

  final bool hasMore;

  final dynamic payload;

  LoadMoreResult(List<T> value, {int loaded, this.hasMore = true, this.payload})
      : assert(value != null),
        this.loaded = loaded ?? value.length,
        super(value);

  factory LoadMoreResult._from(ValueResult<List<T>> result) {
    if (result is LoadMoreResult) {
      return result;
    }
    return LoadMoreResult(result.value);
  }

  ///utils method for result mapping
  static Result<R> map<T, R>(Result<T> result, R Function(T source) map) {
    if (result.isError) return result.asError;
    return Result.value(map(result.asValue.value));
  }
}

///delegate to load more item
///[offset] loaded data length
typedef LoadMoreDelegate<T> = Future<Result<List<T>>> Function(int offset);
