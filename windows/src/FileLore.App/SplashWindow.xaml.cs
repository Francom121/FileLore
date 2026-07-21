using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace FileLore.App;

/// <summary>
/// The branded "FileLore is working" splash: an animated card (spinner arcs,
/// halo ripple, pulsing dots in the brand orange/cream palette) shown while
/// the app starts up or while the Explorer multi-select debounce collects
/// paths, so the gap before a window appears never looks like a hang.
///
/// Lifecycle is owned by <see cref="App.ShowSplash"/> /
/// <see cref="App.CloseSplash"/>; a failsafe timer closes the splash on its
/// own if no window ever claims it (e.g. an unexpected startup stall), so it
/// can never be left on screen forever.
/// </summary>
public partial class SplashWindow : Window
{
    private static readonly TimeSpan Failsafe = TimeSpan.FromSeconds(25);
    private static readonly TimeSpan FadeIn = TimeSpan.FromMilliseconds(180);
    private static readonly TimeSpan FadeOut = TimeSpan.FromMilliseconds(220);

    private readonly DispatcherTimer _failsafe;
    private bool _closing;

    /// <summary>True once the fade-out started — the window is done for.</summary>
    public bool IsFadingOut => _closing;

    public SplashWindow(string message)
    {
        InitializeComponent();
        MessageText.Text = message;

        Loaded += (_, _) => BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, FadeIn));

        _failsafe = new DispatcherTimer { Interval = Failsafe };
        _failsafe.Tick += (_, _) => FadeOutAndClose();
        _failsafe.Start();
    }

    public void UpdateMessage(string message) => MessageText.Text = message;

    /// <summary>Fade out briefly, then close. Safe to call more than once.</summary>
    public void FadeOutAndClose()
    {
        if (_closing) return;
        _closing = true;
        _failsafe.Stop();

        var fade = new DoubleAnimation(0, FadeOut) { FillBehavior = FillBehavior.HoldEnd };
        fade.Completed += (_, _) => Close();
        BeginAnimation(OpacityProperty, fade);
    }

    private void Window_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed) DragMove();
    }
}
