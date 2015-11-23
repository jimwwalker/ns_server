(function () {
  "use strict";

  angular
    .module("mnViews")
    .controller("mnViewsListController", mnViewsListController);

  function mnViewsListController($scope, $state, $uibModal, mnPoolDefault, mnViewsListService, mnViewsEditingService, mnPromiseHelper, mnCompaction, mnHelper, mnPoll) {
    var vm = this;

    vm.showCreationDialog = showCreationDialog;
    vm.showMapreduceCreationDialog = showMapreduceCreationDialog;
    vm.showSpatialCreationDialog = showSpatialCreationDialog;
    vm.showDdocDeletionDialog = showDdocDeletionDialog;
    vm.showViewDeletionDialog = showViewDeletionDialog;
    vm.publishDdoc = publishDdoc;
    vm.copyToDev = copyToDev;
    vm.registerCompactionAsTriggeredAndPost = registerCompactionAsTriggeredAndPost;
    vm.showPublishButton = showPublishButton;
    vm.showCreationButton = showCreationButton;
    vm.showSpatialButton = showSpatialButton;
    vm.showViewCreationButtons = showViewCreationButtons;
    vm.showMatchingWarning = showMatchingWarning;
    vm.getInitialViewsFilterParams = getInitialViewsFilterParams;
    vm.mnPoolDefault = mnPoolDefault.latestValue();
    vm.isDevelopmentViews = $state.params.type === 'development';

    activate();

    function getInitialViewsFilterParams(key, row, isSpatial) {
      return {
        sampleDocumentId: null,
        pageNumber: 0,
        viewId: key,
        full_set: null,
        isSpatial: isSpatial,
        documentId: row.doc.meta.id,
        viewsParams: JSON.stringify(mnViewsEditingService.getInitialViewsFilterParams(isSpatial))
      };
    }
    function showMatchingWarning(row) {
      return row.doc.json.spatial && row.doc.json.views && !_.isEmpty(row.doc.json.spatial) && !_.isEmpty(row.doc.json.views)
    }
    function showViewCreationButtons() {
      return vm.mnViewsListState && $state.params.viewsBucket && vm.isDevelopmentViews && !vm.mnViewsListState.ddocsAreInFactMissing && !vm.mnPoolDefault.value.isROAdminCreds;
    }
    function showPublishButton(row) {
      return vm.isDevelopmentViews && !(row.doc.json.spatial && row.doc.json.views && !_.isEmpty(row.doc.json.spatial) && !_.isEmpty(row.doc.json.views)) && !vm.mnPoolDefault.value.isROAdminCreds;
    }
    function isEmptyView(row) {
      return (!row.doc.json.spatial && !row.doc.json.views || _.isEmpty(row.doc.json.spatial) && _.isEmpty(row.doc.json.views));
    }
    function showCreationButton(row) {
      return vm.isDevelopmentViews && (isEmptyView(row) ||
        (row.doc.json.views && !_.isEmpty(row.doc.json.views) && (!row.doc.json.spatial || _.isEmpty(row.doc.json.spatial)))) && !vm.mnPoolDefault.value.isROAdminCreds;
    }
    function showSpatialButton(row) {
      return vm.isDevelopmentViews && (isEmptyView(row) ||
        (row.doc.json.spatial && !_.isEmpty(row.doc.json.spatial) && (!row.doc.json.views || _.isEmpty(row.doc.json.views)))) && !vm.mnPoolDefault.value.isROAdminCreds;
    }

    function showMapreduceCreationDialog() {
      showCreationDialog(undefined, false);
    }
    function showSpatialCreationDialog() {
      showCreationDialog(undefined, true);
    }

    function showCreationDialog(ddoc, isSpatial) {
      $uibModal.open({
        controller: 'mnViewsCreateDialogController as mnViewsCreateDialogController',
        templateUrl: 'app/mn_admin/mn_views/create_dialog/mn_views_create_dialog.html',
        scope: $scope,
        resolve: {
          currentDdoc: mnHelper.wrapInFunction(ddoc),
          viewType: mnHelper.wrapInFunction(isSpatial ? "spatial" : "views")
        }
      });
    }
    function showDdocDeletionDialog(ddoc) {
      $uibModal.open({
        controller: 'mnViewsDeleteDdocDialogController as mnViewsDeleteDdocDialogController',
        templateUrl: 'app/mn_admin/mn_views/delete_ddoc_dialog/mn_views_delete_ddoc_dialog.html',
        scope: $scope,
        resolve: {
          currentDdocName: mnHelper.wrapInFunction(ddoc.meta.id)
        }
      });
    }
    function showViewDeletionDialog(ddoc, viewName, isSpatial) {
      $uibModal.open({
        controller: 'mnViewsDeleteViewDialogController as mnViewsDeleteViewDialogController',
        templateUrl: 'app/mn_admin/mn_views/delete_view_dialog/mn_views_delete_view_dialog.html',
        scope: $scope,
        resolve: {
          currentDdocName: mnHelper.wrapInFunction(ddoc.meta.id),
          currentViewName: mnHelper.wrapInFunction(viewName),
          isSpatial: mnHelper.wrapInFunction(isSpatial)
        }
      });
    }
    function prepareToPublish(url, ddoc) {
      return function () {
        return mnPromiseHelper(vm, mnViewsListService.createDdoc(url, ddoc.json))
          .onSuccess(function () {
            $state.go('app.admin.views.list', {
              type: 'production'
            });
          })
          .cancelOnScopeDestroy($scope)
          .getPromise();
      };
    }
    function publishDdoc(ddoc) {
      var url = mnViewsListService.getDdocUrl($state.params.viewsBucket, "_design/" + mnViewsListService.cutOffDesignPrefix(ddoc.meta.id));
      var publish = prepareToPublish(url, ddoc);
      mnPromiseHelper(vm, mnViewsListService.getDdoc(url))
        .cancelOnScopeDestroy($scope)
        .getPromise()
        .then(function (presentDdoc) {
          $uibModal.open({
            templateUrl: 'app/mn_admin/mn_views/confirm_dialogs/mn_views_confirm_override_dialog.html'
          }).result.then(publish);
        }, publish);
    }
    function copyToDev(ddoc) {
      $uibModal.open({
        controller: 'mnViewsCopyDialogController as mnViewsCopyDialogController',
        templateUrl: 'app/mn_admin/mn_views/copy_dialog/mn_views_copy_dialog.html',
        scope: $scope,
        resolve: {
          currentDdoc: mnHelper.wrapInFunction(ddoc)
        }
      });
    }
    function registerCompactionAsTriggeredAndPost(row) {
      row.disableCompact = true;
      mnPromiseHelper(vm, mnCompaction.registerAsTriggeredAndPost(row.controllers.compact))
        .reloadState()
        .cancelOnScopeDestroy($scope);
    }
    function activate() {
      if (!$state.params.viewsBucket) {
        vm.mnViewsListState = {};
        return;
      }
      mnPoll
        .start($scope, function () {
          return mnViewsListService.getViewsListState($state.params);
        })
        .subscribe("mnViewsListState", vm)
        .keepIn("app.admin.views.list", vm)
        .cancelOnScopeDestroy()
        .cycle();
    }
  }
})();