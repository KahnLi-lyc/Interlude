import Interlude
import UIKit

/// 局部宿主：HUD 与 Toast 只覆盖卡片区域；返回上一页时自动清理。
final class LocalHostViewController: UIViewController {
    // MARK: - Views

    private lazy var cardView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        return view
    }()

    private lazy var hintLabel: UILabel = {
        let label = UILabel()
        label.text = "HUDs and toasts below attach to this card only.\nThe navigation bar stays interactive."
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }()

    private lazy var buttonStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [
            makeButton("Loading in card", action: #selector(showLoading)),
            makeButton("Progress in card", action: #selector(showProgress)),
            makeButton("Toast in card", action: #selector(showToast)),
            makeButton("Loading, then pop", action: #selector(showAndPop))
        ])
        stack.axis = .vertical
        stack.spacing = 12
        return stack
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Local host"
        view.backgroundColor = .systemBackground
        setupViews()
    }

    // MARK: - View Setup

    private func setupViews() {
        view.addSubview(buttonStack)
        view.addSubview(cardView)
        cardView.addSubview(hintLabel)
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            buttonStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            cardView.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 24),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            cardView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),

            hintLabel.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 20),
            hintLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            hintLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20)
        ])
    }

    // MARK: - Actions

    @objc
    private func showLoading() {
        let token = Interlude.loading("Loading card", on: cardView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            token.finish(.success("Loaded"))
        }
    }

    @objc
    private func showProgress() {
        let token = Interlude.progress(style: .bar, text: "Syncing", on: cardView, interaction: .passthrough)
        DispatchQueue.global().async {
            for step in 1 ... 40 {
                Thread.sleep(forTimeInterval: 0.04)
                token.update(progress: Double(step) / 40)
            }
            token.finish(.success())
        }
    }

    @objc
    private func showToast() {
        Interlude.toast("Only inside the card", icon: .info, on: cardView)
    }

    @objc
    private func showAndPop() {
        Interlude.loading("Leaving…", on: cardView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }

    // MARK: - Private Methods

    private func makeButton(_ title: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.cornerStyle = .large
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
}

/// 键盘避让演示。
final class KeyboardViewController: UIViewController {
    // MARK: - Views

    private lazy var textField: UITextField = {
        let field = UITextField()
        field.placeholder = "Tap here, then show a toast"
        field.borderStyle = .roundedRect
        return field
    }()

    private lazy var button: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Bottom toast"
        configuration.cornerStyle = .large
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: #selector(showToast), for: .touchUpInside)
        return button
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Keyboard"
        view.backgroundColor = .systemBackground

        let stack = UIStackView(arrangedSubviews: [textField, button])
        stack.axis = .vertical
        stack.spacing = 16
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textField.becomeFirstResponder()
    }

    // MARK: - Actions

    @objc
    private func showToast() {
        Interlude.toast("I stay above the keyboard", icon: .info, duration: .long)
    }
}
