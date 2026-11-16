package com.atlasdigital.coastcalendar.ui.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.data.repository.AuthState
import com.atlasdigital.coastcalendar.feature.auth.AuthScreen
import com.atlasdigital.coastcalendar.feature.auth.SessionViewModel
import com.atlasdigital.coastcalendar.feature.create.CreateScreen
import com.atlasdigital.coastcalendar.feature.create.CreateViewModel
import com.atlasdigital.coastcalendar.feature.detail.EventDetailScreen
import com.atlasdigital.coastcalendar.feature.detail.EventDetailViewModel
import com.atlasdigital.coastcalendar.feature.home.HomeScreen
import com.atlasdigital.coastcalendar.feature.home.HomeViewModel
import com.atlasdigital.coastcalendar.feature.hosts.HostsScreen
import com.atlasdigital.coastcalendar.feature.hosts.HostsViewModel
import com.atlasdigital.coastcalendar.feature.hosts.OrganisationPageScreen
import com.atlasdigital.coastcalendar.feature.hosts.OrganisationPageViewModel
import com.atlasdigital.coastcalendar.feature.mylistings.MyListingsScreen
import com.atlasdigital.coastcalendar.feature.mylistings.MyListingsViewModel
import com.atlasdigital.coastcalendar.feature.organisation.OrganisationScreen
import com.atlasdigital.coastcalendar.feature.organisation.OrganisationViewModel
import com.atlasdigital.coastcalendar.feature.settings.ContactSupportScreen
import com.atlasdigital.coastcalendar.feature.settings.ContactSupportViewModel
import com.atlasdigital.coastcalendar.feature.settings.SettingsNav
import com.atlasdigital.coastcalendar.feature.settings.SettingsScreen
import com.atlasdigital.coastcalendar.feature.settings.SettingsViewModel
import com.atlasdigital.coastcalendar.feature.support.SupportDashboardScreen
import com.atlasdigital.coastcalendar.feature.support.SupportDashboardViewModel
import com.atlasdigital.coastcalendar.feature.welcome.WelcomeSheet
import com.atlasdigital.coastcalendar.feature.whatson.WhatsOnScreen
import com.atlasdigital.coastcalendar.feature.whatson.WhatsOnViewModel
import com.atlasdigital.coastcalendar.ui.theme.PccColors

/** Same five tabs as iOS RootTabView: Home · What's On · Create · Hosts · Settings. */
enum class Tab(val route: String, val label: String, val icon: ImageVector) {
    Home("home", "Home", Icons.Filled.Home),
    WhatsOn("whats_on", "What's On", Icons.Filled.DateRange),
    Create("create", "Create", Icons.Filled.AddCircle),
    Hosts("hosts", "Hosts", Icons.Filled.Person),
    Settings("settings", "Settings", Icons.Filled.Settings),
}

private const val AUTH_ROUTE = "auth"
private const val EVENT_ROUTE = "event/{id}"
private fun eventRoute(id: String) = "event/$id"
private const val MY_LISTINGS_ROUTE = "mylistings"
private const val CONTACT_ROUTE = "contact"
private const val DELETE_ACCOUNT_ROUTE = "delete-account"
private const val ORGANISATION_ROUTE = "organisation"
private const val ORG_PAGE_ROUTE = "org/{id}"
private fun orgPageRoute(id: String) = "org/$id"
internal const val SUPPORT_ROUTE = "support"

/** Pushed screens hide the tab bar like iOS NavigationStack pushes. */
private val PUSHED_ROUTES = setOf(AUTH_ROUTE, EVENT_ROUTE, MY_LISTINGS_ROUTE, CONTACT_ROUTE, DELETE_ACCOUNT_ROUTE, ORGANISATION_ROUTE, ORG_PAGE_ROUTE, SUPPORT_ROUTE)

@Composable
fun CoastCalendarRoot(container: AppContainer, openEventId: String? = null, onOpenedEvent: () -> Unit = {}) {
    val session: SessionViewModel = viewModel { SessionViewModel(container) }
    val authState by session.authState.collectAsState()
    val showWelcome by session.showWelcome.collectAsState()
    val nav = rememberNavController()
    // Reminder notification tap: open that listing (detail loads it by id if it isn't cached).
    androidx.compose.runtime.LaunchedEffect(openEventId) {
        val id = openEventId ?: return@LaunchedEffect
        nav.navigate(eventRoute(id.lowercase()))
        onOpenedEvent()
    }
    val backStack by nav.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val user = (authState as? AuthState.SignedIn)?.session

    if (authState is AuthState.Loading) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = PccColors.PohutukawaRed) }
        return
    }

    fun go(route: String) = nav.navigate(route) {
        popUpTo(nav.graph.findStartDestination().id) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }

    androidx.compose.runtime.CompositionLocalProvider(
        com.atlasdigital.coastcalendar.ui.components.LocalAppContainer provides container,
        com.atlasdigital.coastcalendar.ui.components.LocalUserSession provides user,
    ) {
    Scaffold(
        containerColor = PccColors.Cream,
        bottomBar = {
            if (currentRoute !in PUSHED_ROUTES) {
                NavigationBar(containerColor = Color.White.copy(alpha = 0.96f)) {
                    Tab.entries.forEach { tab ->
                        NavigationBarItem(
                            selected = currentRoute == tab.route,
                            onClick = { go(tab.route) },
                            icon = { Icon(tab.icon, contentDescription = null) },
                            label = { Text(tab.label, maxLines = 1) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = PccColors.PohutukawaRed,
                                selectedTextColor = PccColors.PohutukawaRed,
                                indicatorColor = PccColors.PohutukawaRed.copy(alpha = 0.10f),
                                unselectedIconColor = PccColors.Text,
                                unselectedTextColor = PccColors.Text,
                            ),
                        )
                    }
                }
            }
        },
    ) { padding ->
        NavHost(navController = nav, startDestination = Tab.Home.route) {
            composable(Tab.Home.route) {
                val vm: HomeViewModel = viewModel { HomeViewModel(container) }
                HomeScreen(vm, user, padding, onOpen = { nav.navigate(eventRoute(it)) })
            }
            composable(Tab.WhatsOn.route) {
                val vm: WhatsOnViewModel = viewModel { WhatsOnViewModel(container) }
                WhatsOnScreen(vm, padding, onOpen = { nav.navigate(eventRoute(it)) })
            }
            composable(Tab.Create.route) {
                val vm: CreateViewModel = viewModel { CreateViewModel(container) }
                CreateScreen(
                    viewModel = vm,
                    session = user,
                    contentPadding = padding,
                    onSignIn = { nav.navigate(AUTH_ROUTE) },
                    onResendVerification = session::resendVerification,
                    onRefreshUser = { session.refreshUser() },
                )
            }
            composable(Tab.Hosts.route) {
                val vm: HostsViewModel = viewModel { HostsViewModel(container) }
                HostsScreen(vm, padding, onOpenHost = { nav.navigate(orgPageRoute(it)) })
            }
            composable(Tab.Settings.route) {
                val vm: SettingsViewModel = viewModel { SettingsViewModel(container) }
                SettingsScreen(
                    viewModel = vm,
                    session = user,
                    contentPadding = padding,
                    nav = SettingsNav(
                        onSignIn = { nav.navigate(AUTH_ROUTE) },
                        onSignOut = { session.signOut() },
                        onShowWelcome = session::showWelcomeAgain,
                        onMyListings = { nav.navigate(MY_LISTINGS_ROUTE) },
                        onOrganisation = { nav.navigate(ORGANISATION_ROUTE) },
                        onContactSupport = { nav.navigate(CONTACT_ROUTE) },
                        onSupportDashboard = { nav.navigate(SUPPORT_ROUTE) },
                        onDeleteAccount = { nav.navigate(DELETE_ACCOUNT_ROUTE) },
                    ),
                )
            }
            composable(MY_LISTINGS_ROUTE) {
                val vm: MyListingsViewModel = viewModel { MyListingsViewModel(container) }
                MyListingsScreen(vm, user, onBack = { nav.popBackStack() }, onSignIn = { nav.navigate(AUTH_ROUTE) }, onOpen = { nav.navigate(eventRoute(it)) })
            }
            composable(CONTACT_ROUTE) {
                val vm: ContactSupportViewModel = viewModel { ContactSupportViewModel(container) }
                ContactSupportScreen(vm, user, onBack = { nav.popBackStack() }, onSignIn = { nav.navigate(AUTH_ROUTE) })
            }
            composable(DELETE_ACCOUNT_ROUTE) {
                val vm: com.atlasdigital.coastcalendar.feature.settings.AccountDeletionViewModel =
                    viewModel { com.atlasdigital.coastcalendar.feature.settings.AccountDeletionViewModel(container) }
                com.atlasdigital.coastcalendar.feature.settings.AccountDeletionScreen(vm, user, onBack = { nav.popBackStack() }, onSignIn = { nav.navigate(AUTH_ROUTE) })
            }
            composable(ORGANISATION_ROUTE) {
                val vm: OrganisationViewModel = viewModel { OrganisationViewModel(container) }
                OrganisationScreen(vm, user, onBack = { nav.popBackStack() }, onSignIn = { nav.navigate(AUTH_ROUTE) }, onOpenPage = { nav.navigate(orgPageRoute(it)) })
            }
            composable(SUPPORT_ROUTE) {
                val vm: SupportDashboardViewModel = viewModel { SupportDashboardViewModel(container) }
                SupportDashboardScreen(vm, user, onBack = { nav.popBackStack() }, onOpen = { nav.navigate(eventRoute(it)) })
            }
            composable(ORG_PAGE_ROUTE) { entry ->
                val id = entry.arguments?.getString("id").orEmpty()
                val vm: OrganisationPageViewModel = viewModel(key = "org-$id") { OrganisationPageViewModel(container, id) }
                OrganisationPageScreen(vm, user, onBack = { nav.popBackStack() }, onSignIn = { nav.navigate(AUTH_ROUTE) }, onOpen = { nav.navigate(eventRoute(it)) })
            }
            composable(EVENT_ROUTE) { entry ->
                val id = entry.arguments?.getString("id").orEmpty()
                val vm: EventDetailViewModel = viewModel(key = "detail-$id") { EventDetailViewModel(container, id) }
                EventDetailScreen(
                    vm, user,
                    onBack = { nav.popBackStack() },
                    onSignIn = { nav.navigate(AUTH_ROUTE) },
                    onOpenOrganisation = { nav.navigate(orgPageRoute(it)) },
                )
            }
            composable(AUTH_ROUTE) {
                AuthScreen(session, onSignedIn = { nav.popBackStack() }, onBack = { nav.popBackStack() })
            }
        }
    }

    }

    if (showWelcome) {
        WelcomeSheet(onDismiss = session::dismissWelcome)
    }
}
