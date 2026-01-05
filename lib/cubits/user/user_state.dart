part of 'user_cubit.dart';

abstract class UserState {
  const UserState();
}

class UserInitial extends UserState {
  const UserInitial();
}

class UserLoading extends UserState {
  const UserLoading();
}

class UserLoaded extends UserState {
  final UserModel currentUser;
  final List<UserModel> leaderboard;

  const UserLoaded({required this.currentUser, this.leaderboard = const []});

  @override
  List<Object?> get props => [currentUser, leaderboard];

  UserLoaded copyWith({UserModel? currentUser, List<UserModel>? leaderboard}) {
    return UserLoaded(
      currentUser: currentUser ?? this.currentUser,
      leaderboard: leaderboard ?? this.leaderboard,
    );
  }
}

class UserError extends UserState {
  final String message;

  const UserError({required this.message});

  @override
  List<Object?> get props => [message];
}
