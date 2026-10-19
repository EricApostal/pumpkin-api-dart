/// `UnpackingHandler` (Create's package unpacking API): how a package's contents are inserted
/// into the inventory of a package port target. The implementations live in the logistics module.
library;

export '../../logistics/packager/unpacking.dart'
    show
        DefaultUnpackingHandler,
        UnpackingHandler,
        UnpackingHandlers,
        VoidingUnpackingHandler;
