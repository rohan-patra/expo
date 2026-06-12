import ExpoModulesCore
import ExpoModulesJSI
import UIKit

struct Point: Record {
  @Field
  var x: Double = 0

  @Field
  var y: Double = 0
}

@Record
struct SynthesizedPoint {
  var x: Double = 0
  var y: Double = 0
}

final class SharedPoint: SharedObject {
  var x: Double = 0
  var y: Double = 0
}

// MARK: - View-props benchmark

/// A record-typed prop. Uses the `@Record` macro, which synthesizes a compile-time
/// `from(object:appContext:)` factory and so bypasses the `Mirror`/`fieldsOf` reflection that
/// dominated decode cost for `@Field`-based records (see the JSI view-props profiling). The JSI
/// decode path calls `from(object:)`, which dispatches to this synthesized factory.
@Record
struct BenchmarkStyle {
  var opacity: Double = 1
  var cornerRadius: Double = 0
  var label: String = ""
  var weight: Int = 0
}

/// A UIView with a wide, varied set of JS-thread-decodable props (primitives, strings, an array,
/// and a record) so a prop-update loop exercises the decoding path meaningfully. A few props are
/// rendered for live confirmation that decode → apply lands the right values: `color` → background,
/// `title`/`count` → an overlaid label. The setters are still cheap, but note the label text +
/// background updates add a little real apply work (per the benchmark, that's representative —
/// real views do work in their setters).
final class BenchmarkView: ExpoView {
  // The label (fully owned, fills bounds) doubles as the colored background. We can't use the
  // view's own `backgroundColor`: `RCTViewComponentView` (this view's Fabric base) overrides that
  // setter to only stash the color and apply it via a private backing layer during ITS prop-diff —
  // so a direct `backgroundColor =` never repaints. Setting it on the label sidesteps RN's layer
  // management.
  private let label = UILabel()

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    label.textColor = .white
    label.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
    label.textAlignment = .center
    addSubview(label)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    label.frame = bounds
  }

  private func updateLabel() {
    label.text = "\(title)  ·  #\(count)"
  }

  var color: UIColor = .clear {
    didSet {
      label.backgroundColor = color
    }
  }
  var title: String = "" {
    didSet {
      updateLabel()
    }
  }
  var count: Int = 0 {
    didSet {
      updateLabel()
    }
  }
  var decoration = BenchmarkStyle()
  var values: [Double] = []
}

@ExpoModule
public final class BenchmarkingExpoModule: Module {
  public func definition() -> ModuleDefinition {
    Function("nothing") {}
    Function("nothingOptimized", nothingOptimized())

    AsyncFunction("nothingAsync") { () async -> Void in }

    // MARK: - Numbers

    Function("addNumbers") { (a: Double, b: Double) in
      return a + b
    }

    Function("addNumbersOptimized", addNumbersOptimized())

    AsyncFunction("addNumbersAsync") { (a: Double, b: Double) in
      return a + b
    }

    AsyncFunction("addNumbersAsyncOptimized", addNumbersOptimized())

    // MARK: - Strings

    Function("addStrings") { (a: String, b: String) in
      return a + b
    }

    Function("addStringsOptimized", addStringsOptimized())

    // MARK: - Arrays

    Function("foldArray") { (array: [Double]) in
      return array.reduce(0.0, +)
    }

    // MARK: - Passthrough

    Function("passthroughDict") { (point: [String: Any]) in
      return point
    }

    Function("passthroughRecord") { (point: Point) in
      return point
    }

    Function("passthroughSharedObject") { (point: SharedPoint) in
      return point
    }

    Class(SharedPoint.self) {
      Constructor { (x: Double, y: Double) -> SharedPoint in
        let point = SharedPoint()
        point.x = x
        point.y = y
        return point
      }

      Property("x") { (point: SharedPoint) in
        return point.x
      }

      Property("y") { (point: SharedPoint) in
        return point.y
      }
    }

    // MARK: - View-props benchmark
    //
    // `getViewPropsBenchmark` / `resetViewPropsBenchmark` read the process-wide counters that
    // expo-modules-core accumulates around view-prop decode (JS thread) and apply (main
    // thread). Drive the `BenchmarkView` below with changing props, then read the totals.

    Function("resetViewPropsBenchmark") {
      ViewPropsBenchmark.reset()
    }

    Function("getViewPropsBenchmark") { () -> [String: Any] in
      return ViewPropsBenchmark.snapshot()
    }

    View(BenchmarkView.self) {
      Prop("color") { (view: BenchmarkView, color: UIColor) in
        view.color = color
      }
      Prop("decoration") { (view: BenchmarkView, decoration: BenchmarkStyle) in
        view.decoration = decoration
      }
      Prop("values") { (view: BenchmarkView, values: [Double]) in
        view.values = values
      }
      Prop("flag") { (view: BenchmarkView, flag: Bool) in
        view.tag = flag ? 1 : 0
      }
      Prop("count") { (view: BenchmarkView, count: Int) in
        view.count = count
      }
      Prop("ratio") { (view: BenchmarkView, ratio: Double) in
        _ = ratio
      }
      Prop("title") { (view: BenchmarkView, title: String) in
        view.title = title
      }
      Prop("subtitle") { (view: BenchmarkView, subtitle: String) in
        view.accessibilityHint = subtitle
      }
    }

    // MARK: - runtime.execute() benchmarks
    //
    // Each benchmark times `iterations` round-trips of one of the four
    // `JavaScriptRuntime.execute(...)` overloads from a non-JS thread, returning
    // elapsed milliseconds. AsyncFunction bodies already run off the JS thread,
    // so calling `execute` here exercises the cross-thread scheduling + wakeup
    // path.
    //
    // The two non-async closures dispatch onto the GCD queue shared by Expo
    // Modules; the two async closures dispatch onto a Swift Concurrency
    // executor. Both call the same `RuntimeScheduler` underneath, but the
    // caller side differs.

    // Caller: GCD queue. Closure: sync.
    AsyncFunction("executeBlockingSync") { (iterations: Int) throws -> Double in
      let runtime = try self.appContext!.runtime
      let start = DispatchTime.now()
      for _ in 0..<iterations {
        try runtime.execute { () -> Void in
          _ = runtime.global().hasProperty("Math")
        }
      }
      return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    // Caller: GCD queue. Closure: async.
    AsyncFunction("executeBlockingAsync") { (iterations: Int) throws -> Double in
      let runtime = try self.appContext!.runtime
      let start = DispatchTime.now()
      for _ in 0..<iterations {
        try runtime.execute { @JavaScriptActor () async -> Void in
          _ = runtime.global().hasProperty("Math")
        }
      }
      return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    // Caller: Swift Concurrency (detached Task). Closure: sync.
    // The detached Task runs on the cooperative pool — off the JS thread — so
    // each `await runtime.execute(...)` exercises the cross-thread scheduling
    // path instead of the same-thread fast path.
    AsyncFunction("executeAsyncSync") { (iterations: Int, promise: Promise) in
      let runtime = try self.appContext!.runtime
      Task.detached {
        do {
          let start = DispatchTime.now()
          for _ in 0..<iterations {
            try await runtime.execute { () -> Void in
              _ = runtime.global().hasProperty("Math")
            }
          }
          let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
          promise.resolve(elapsedMs)
        } catch {
          promise.reject(error)
        }
      }
    }

    // Caller: Swift Concurrency (detached Task). Closure: async.
    AsyncFunction("executeAsyncAsync") { (iterations: Int, promise: Promise) in
      let runtime = try self.appContext!.runtime
      Task.detached {
        do {
          let start = DispatchTime.now()
          for _ in 0..<iterations {
            try await runtime.execute { @JavaScriptActor () async -> Void in
              _ = runtime.global().hasProperty("Math")
            }
          }
          let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
          promise.resolve(elapsedMs)
        } catch {
          promise.reject(error)
        }
      }
    }
  }

  @JS
  private func nothingSynthesized() -> Void {}

  @JS
  private func nothingAsyncSynthesized() async -> Void {}

  @OptimizedFunction
  private func nothingOptimized() -> Void {}

  @JS
  private func addNumbersSynthesized(a: Double, b: Double) throws -> Double {
    return a + b
  }

  @JS
  private func addNumbersAsyncSynthesized(a: Double, b: Double) async throws -> Double {
    return a + b
  }

  @OptimizedFunction
  private func addNumbersOptimized(a: Double, b: Double) throws -> Double {
    return a + b
  }

  @JS
  private func addStringsSynthesized(a: String, b: String) throws -> String {
    return a + b
  }

  @OptimizedFunction
  private func addStringsOptimized(a: String, b: String) throws -> String {
    return a + b
  }

  @JS
  private func foldArraySynthesized(array: [Double]) -> Double {
    return array.reduce(0.0, +)
  }

  @JS
  private func passthroughSynthesizedRecord(point: SynthesizedPoint) -> SynthesizedPoint {
    return point
  }
}
